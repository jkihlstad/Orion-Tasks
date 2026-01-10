import { internalMutation, internalQuery, MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";

/**
 * Event Projector Logic
 *
 * This module handles the projection of events into materialized views.
 * It follows the event sourcing pattern where events are the source of truth
 * and projections are derived read models optimized for queries.
 *
 * Event Types Supported:
 * - tasks.list.created / updated / deleted
 * - tasks.task.created / updated / deleted / completed / uncompleted
 * - tasks.tag.created / updated / deleted
 */

// ============================================================================
// Types
// ============================================================================

interface TaskEvent {
  _id: Id<"events">;
  eventId: string;
  userId: string;
  deviceId: string;
  appId: string;
  timestamp: number;
  serverTimestamp: number;
  eventType: string;
  schemaVersion: number;
  payload: any;
  mediaRefs?: any[];
  consentSnapshotId: string;
  processingStatus?: string;
}

interface ListPayload {
  listId: string;
  name?: string;
  color?: string;
  icon?: string;
  sortOrder?: number;
  smartList?: boolean;
  smartListType?: string;
}

interface TaskPayload {
  taskId: string;
  listId?: string;
  title?: string;
  notes?: string;
  dueDate?: string | null;
  dueTime?: string | null;
  priority?: "none" | "low" | "medium" | "high";
  tags?: string[];
  flag?: boolean;
  completed?: boolean;
  completedAt?: string | null;
  redBeaconEnabled?: boolean;
  mirrorToCalendar?: boolean;
  calendarEventId?: string | null;
  recurrence?: any;
  subtasks?: any[];
  attachments?: any[];
  location?: any;
  url?: string | null;
  sortOrder?: number;
}

interface TagPayload {
  tagId: string;
  name?: string;
  color?: string;
}

// ============================================================================
// Event Processing Entry Point
// ============================================================================

/**
 * Process a single event and update projections
 *
 * This is the main entry point for event processing.
 * It routes events to the appropriate handler based on event type.
 */
export const processEvent = internalMutation({
  args: {
    eventId: v.id("events"),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);
    if (!event) {
      throw new Error(`Event not found: ${args.eventId}`);
    }

    const eventType = event.eventType;

    // Route to appropriate handler
    if (eventType.startsWith("tasks.list.")) {
      await processListEvent(ctx, event as TaskEvent);
    } else if (eventType.startsWith("tasks.task.")) {
      await processTaskEvent(ctx, event as TaskEvent);
    } else if (eventType.startsWith("tasks.tag.")) {
      await processTagEvent(ctx, event as TaskEvent);
    } else {
      // Unknown event type - log but don't fail
      console.warn(`Unknown event type: ${eventType}`);
    }

    return { processed: true, eventType };
  },
});

/**
 * Process a batch of events
 *
 * Processes events in order, maintaining consistency.
 */
export const processEventBatch = internalMutation({
  args: {
    eventIds: v.array(v.id("events")),
  },
  handler: async (ctx, args) => {
    const results: { eventId: Id<"events">; processed: boolean; error?: string }[] = [];

    for (const eventId of args.eventIds) {
      try {
        const event = await ctx.db.get(eventId);
        if (!event) {
          results.push({ eventId, processed: false, error: "Event not found" });
          continue;
        }

        const eventType = event.eventType;

        if (eventType.startsWith("tasks.list.")) {
          await processListEvent(ctx, event as TaskEvent);
        } else if (eventType.startsWith("tasks.task.")) {
          await processTaskEvent(ctx, event as TaskEvent);
        } else if (eventType.startsWith("tasks.tag.")) {
          await processTagEvent(ctx, event as TaskEvent);
        }

        results.push({ eventId, processed: true });
      } catch (error) {
        console.error(`Error processing event ${eventId}:`, error);
        results.push({
          eventId,
          processed: false,
          error: error instanceof Error ? error.message : "Unknown error",
        });
      }
    }

    return results;
  },
});

// ============================================================================
// List Event Handlers
// ============================================================================

async function processListEvent(ctx: MutationCtx, event: TaskEvent): Promise<void> {
  const payload = event.payload as ListPayload;
  const eventType = event.eventType;

  switch (eventType) {
    case "tasks.list.created":
      await createListProjection(ctx, event, payload);
      break;

    case "tasks.list.updated":
      await updateListProjection(ctx, event, payload);
      break;

    case "tasks.list.deleted":
      await deleteListProjection(ctx, event, payload);
      break;

    case "tasks.list.reordered":
      await reorderListProjection(ctx, event, payload);
      break;

    default:
      console.warn(`Unknown list event type: ${eventType}`);
  }
}

async function createListProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: ListPayload
): Promise<void> {
  // Check if list already exists (idempotency)
  const existing = await ctx.db
    .query("taskListsProjection")
    .withIndex("by_list_id", (q) => q.eq("listId", payload.listId))
    .first();

  if (existing) {
    // List already exists - update if this event is newer
    if (event.timestamp > existing.updatedAt) {
      await ctx.db.patch(existing._id, {
        name: payload.name ?? existing.name,
        color: payload.color ?? existing.color,
        icon: payload.icon ?? existing.icon,
        sortOrder: payload.sortOrder ?? existing.sortOrder,
        smartList: payload.smartList ?? existing.smartList,
        smartListType: payload.smartListType ?? existing.smartListType,
        updatedAt: event.timestamp,
        lastEventId: event.eventId,
      });
    }
    return;
  }

  // Create new list projection
  await ctx.db.insert("taskListsProjection", {
    listId: payload.listId,
    userId: event.userId,
    name: payload.name ?? "Untitled List",
    color: payload.color ?? "#007AFF",
    icon: payload.icon ?? "list.bullet",
    sortOrder: payload.sortOrder ?? 0,
    createdAt: event.timestamp,
    updatedAt: event.timestamp,
    tombstoned: false,
    smartList: payload.smartList,
    smartListType: payload.smartListType,
    taskCount: 0,
    completedTaskCount: 0,
    lastEventId: event.eventId,
  });
}

async function updateListProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: ListPayload
): Promise<void> {
  const existing = await ctx.db
    .query("taskListsProjection")
    .withIndex("by_list_id", (q) => q.eq("listId", payload.listId))
    .first();

  if (!existing) {
    // List doesn't exist - create it
    await createListProjection(ctx, event, payload);
    return;
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  const updates: Partial<Doc<"taskListsProjection">> = {
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  };

  if (payload.name !== undefined) updates.name = payload.name;
  if (payload.color !== undefined) updates.color = payload.color;
  if (payload.icon !== undefined) updates.icon = payload.icon;
  if (payload.sortOrder !== undefined) updates.sortOrder = payload.sortOrder;
  if (payload.smartList !== undefined) updates.smartList = payload.smartList;
  if (payload.smartListType !== undefined) updates.smartListType = payload.smartListType;

  await ctx.db.patch(existing._id, updates);
}

async function deleteListProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: ListPayload
): Promise<void> {
  const existing = await ctx.db
    .query("taskListsProjection")
    .withIndex("by_list_id", (q) => q.eq("listId", payload.listId))
    .first();

  if (!existing) {
    return; // Nothing to delete
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  // Soft delete (tombstone)
  await ctx.db.patch(existing._id, {
    tombstoned: true,
    tombstonedAt: event.timestamp,
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  });

  // Also tombstone all tasks in this list
  const tasks = await ctx.db
    .query("tasksProjection")
    .withIndex("by_list", (q) => q.eq("listId", payload.listId))
    .collect();

  for (const task of tasks) {
    if (!task.tombstoned) {
      await ctx.db.patch(task._id, {
        tombstoned: true,
        tombstonedAt: event.timestamp,
        updatedAt: event.timestamp,
        lastEventId: event.eventId,
      });
    }
  }
}

async function reorderListProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: ListPayload
): Promise<void> {
  const existing = await ctx.db
    .query("taskListsProjection")
    .withIndex("by_list_id", (q) => q.eq("listId", payload.listId))
    .first();

  if (!existing || event.timestamp <= existing.updatedAt) {
    return;
  }

  if (payload.sortOrder !== undefined) {
    await ctx.db.patch(existing._id, {
      sortOrder: payload.sortOrder,
      updatedAt: event.timestamp,
      lastEventId: event.eventId,
    });
  }
}

// ============================================================================
// Task Event Handlers
// ============================================================================

async function processTaskEvent(ctx: MutationCtx, event: TaskEvent): Promise<void> {
  const payload = event.payload as TaskPayload;
  const eventType = event.eventType;

  switch (eventType) {
    case "tasks.task.created":
      await createTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.updated":
      await updateTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.deleted":
      await deleteTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.completed":
      await completeTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.uncompleted":
      await uncompleteTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.moved":
      await moveTaskProjection(ctx, event, payload);
      break;

    case "tasks.task.reordered":
      await reorderTaskProjection(ctx, event, payload);
      break;

    default:
      console.warn(`Unknown task event type: ${eventType}`);
  }
}

async function createTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  // Check if task already exists (idempotency)
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (existing) {
    // Task already exists - update if this event is newer
    if (event.timestamp > existing.updatedAt) {
      await updateTaskFromPayload(ctx, existing._id, event, payload, existing);
    }
    return;
  }

  // Verify list exists
  if (!payload.listId) {
    console.error(`Cannot create task without listId: ${payload.taskId}`);
    return;
  }

  // Create new task projection
  await ctx.db.insert("tasksProjection", {
    taskId: payload.taskId,
    userId: event.userId,
    listId: payload.listId,
    title: payload.title ?? "Untitled Task",
    notes: payload.notes,
    dueDate: payload.dueDate ?? undefined,
    dueTime: payload.dueTime ?? undefined,
    priority: payload.priority ?? "none",
    tags: payload.tags ?? [],
    flag: payload.flag ?? false,
    completed: payload.completed ?? false,
    completedAt: payload.completedAt ?? undefined,
    redBeaconEnabled: payload.redBeaconEnabled ?? false,
    mirrorToCalendar: payload.mirrorToCalendar ?? false,
    calendarEventId: payload.calendarEventId ?? undefined,
    recurrence: payload.recurrence,
    subtasks: payload.subtasks ?? [],
    attachments: payload.attachments ?? [],
    location: payload.location,
    url: payload.url ?? undefined,
    sortOrder: payload.sortOrder ?? 0,
    createdAt: event.timestamp,
    updatedAt: event.timestamp,
    tombstoned: false,
    lastEventId: event.eventId,
  });

  // Update list task count
  await updateListTaskCount(ctx, payload.listId, 1, 0);
}

async function updateTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing) {
    // Task doesn't exist - create it if we have enough info
    if (payload.listId) {
      await createTaskProjection(ctx, event, payload);
    }
    return;
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  await updateTaskFromPayload(ctx, existing._id, event, payload, existing);
}

async function updateTaskFromPayload(
  ctx: MutationCtx,
  taskId: Id<"tasksProjection">,
  event: TaskEvent,
  payload: TaskPayload,
  existing: Doc<"tasksProjection">
): Promise<void> {
  const updates: Partial<Doc<"tasksProjection">> = {
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  };

  if (payload.title !== undefined) updates.title = payload.title;
  if (payload.notes !== undefined) updates.notes = payload.notes;
  if (payload.dueDate !== undefined) updates.dueDate = payload.dueDate ?? undefined;
  if (payload.dueTime !== undefined) updates.dueTime = payload.dueTime ?? undefined;
  if (payload.priority !== undefined) updates.priority = payload.priority;
  if (payload.tags !== undefined) updates.tags = payload.tags;
  if (payload.flag !== undefined) updates.flag = payload.flag;
  if (payload.completed !== undefined) updates.completed = payload.completed;
  if (payload.completedAt !== undefined) updates.completedAt = payload.completedAt ?? undefined;
  if (payload.redBeaconEnabled !== undefined) updates.redBeaconEnabled = payload.redBeaconEnabled;
  if (payload.mirrorToCalendar !== undefined) updates.mirrorToCalendar = payload.mirrorToCalendar;
  if (payload.calendarEventId !== undefined) updates.calendarEventId = payload.calendarEventId ?? undefined;
  if (payload.recurrence !== undefined) updates.recurrence = payload.recurrence ?? undefined;
  if (payload.subtasks !== undefined) updates.subtasks = payload.subtasks;
  if (payload.attachments !== undefined) updates.attachments = payload.attachments;
  if (payload.location !== undefined) updates.location = payload.location ?? undefined;
  if (payload.url !== undefined) updates.url = payload.url ?? undefined;
  if (payload.sortOrder !== undefined) updates.sortOrder = payload.sortOrder;

  // Handle list change
  if (payload.listId !== undefined && payload.listId !== existing.listId) {
    updates.listId = payload.listId;
    // Update counts on both lists
    await updateListTaskCount(ctx, existing.listId, -1, existing.completed ? -1 : 0);
    await updateListTaskCount(ctx, payload.listId, 1, existing.completed ? 1 : 0);
  }

  await ctx.db.patch(taskId, updates);
}

async function deleteTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing) {
    return; // Nothing to delete
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  // Soft delete (tombstone)
  await ctx.db.patch(existing._id, {
    tombstoned: true,
    tombstonedAt: event.timestamp,
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  });

  // Update list task count
  await updateListTaskCount(
    ctx,
    existing.listId,
    -1,
    existing.completed ? -1 : 0
  );
}

async function completeTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing) {
    return;
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  const wasCompleted = existing.completed;

  await ctx.db.patch(existing._id, {
    completed: true,
    completedAt: payload.completedAt ?? new Date(event.timestamp).toISOString(),
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  });

  // Update list completed count if status changed
  if (!wasCompleted) {
    await updateListTaskCount(ctx, existing.listId, 0, 1);
  }
}

async function uncompleteTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing) {
    return;
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  const wasCompleted = existing.completed;

  await ctx.db.patch(existing._id, {
    completed: false,
    completedAt: undefined,
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  });

  // Update list completed count if status changed
  if (wasCompleted) {
    await updateListTaskCount(ctx, existing.listId, 0, -1);
  }
}

async function moveTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing || !payload.listId) {
    return;
  }

  // Only update if this event is newer
  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  const oldListId = existing.listId;
  const newListId = payload.listId;

  if (oldListId !== newListId) {
    await ctx.db.patch(existing._id, {
      listId: newListId,
      sortOrder: payload.sortOrder ?? existing.sortOrder,
      updatedAt: event.timestamp,
      lastEventId: event.eventId,
    });

    // Update counts on both lists
    await updateListTaskCount(ctx, oldListId, -1, existing.completed ? -1 : 0);
    await updateListTaskCount(ctx, newListId, 1, existing.completed ? 1 : 0);
  }
}

async function reorderTaskProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TaskPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tasksProjection")
    .withIndex("by_task_id", (q) => q.eq("taskId", payload.taskId))
    .first();

  if (!existing || event.timestamp <= existing.updatedAt) {
    return;
  }

  if (payload.sortOrder !== undefined) {
    await ctx.db.patch(existing._id, {
      sortOrder: payload.sortOrder,
      updatedAt: event.timestamp,
      lastEventId: event.eventId,
    });
  }
}

// ============================================================================
// Tag Event Handlers
// ============================================================================

async function processTagEvent(ctx: MutationCtx, event: TaskEvent): Promise<void> {
  const payload = event.payload as TagPayload;
  const eventType = event.eventType;

  switch (eventType) {
    case "tasks.tag.created":
      await createTagProjection(ctx, event, payload);
      break;

    case "tasks.tag.updated":
      await updateTagProjection(ctx, event, payload);
      break;

    case "tasks.tag.deleted":
      await deleteTagProjection(ctx, event, payload);
      break;

    default:
      console.warn(`Unknown tag event type: ${eventType}`);
  }
}

async function createTagProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TagPayload
): Promise<void> {
  // Check if tag already exists (idempotency)
  const existing = await ctx.db
    .query("tagsProjection")
    .withIndex("by_tag_id", (q) => q.eq("tagId", payload.tagId))
    .first();

  if (existing) {
    if (event.timestamp > existing.updatedAt) {
      await ctx.db.patch(existing._id, {
        name: payload.name ?? existing.name,
        color: payload.color ?? existing.color,
        updatedAt: event.timestamp,
        lastEventId: event.eventId,
      });
    }
    return;
  }

  await ctx.db.insert("tagsProjection", {
    tagId: payload.tagId,
    userId: event.userId,
    name: payload.name ?? "Untitled Tag",
    color: payload.color ?? "#8E8E93",
    createdAt: event.timestamp,
    updatedAt: event.timestamp,
    tombstoned: false,
    taskCount: 0,
    lastEventId: event.eventId,
  });
}

async function updateTagProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TagPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tagsProjection")
    .withIndex("by_tag_id", (q) => q.eq("tagId", payload.tagId))
    .first();

  if (!existing) {
    await createTagProjection(ctx, event, payload);
    return;
  }

  if (event.timestamp <= existing.updatedAt) {
    return;
  }

  const updates: Partial<Doc<"tagsProjection">> = {
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  };

  if (payload.name !== undefined) updates.name = payload.name;
  if (payload.color !== undefined) updates.color = payload.color;

  await ctx.db.patch(existing._id, updates);
}

async function deleteTagProjection(
  ctx: MutationCtx,
  event: TaskEvent,
  payload: TagPayload
): Promise<void> {
  const existing = await ctx.db
    .query("tagsProjection")
    .withIndex("by_tag_id", (q) => q.eq("tagId", payload.tagId))
    .first();

  if (!existing || event.timestamp <= existing.updatedAt) {
    return;
  }

  await ctx.db.patch(existing._id, {
    tombstoned: true,
    tombstonedAt: event.timestamp,
    updatedAt: event.timestamp,
    lastEventId: event.eventId,
  });
}

// ============================================================================
// Helper Functions
// ============================================================================

async function updateListTaskCount(
  ctx: MutationCtx,
  listId: string,
  taskDelta: number,
  completedDelta: number
): Promise<void> {
  const list = await ctx.db
    .query("taskListsProjection")
    .withIndex("by_list_id", (q) => q.eq("listId", listId))
    .first();

  if (!list) {
    return;
  }

  const newTaskCount = Math.max(0, (list.taskCount ?? 0) + taskDelta);
  const newCompletedCount = Math.max(0, (list.completedTaskCount ?? 0) + completedDelta);

  await ctx.db.patch(list._id, {
    taskCount: newTaskCount,
    completedTaskCount: newCompletedCount,
  });
}

// ============================================================================
// Query Helpers for Projections
// ============================================================================

/**
 * Get a task by ID
 */
export const getTaskById = internalQuery({
  args: {
    taskId: v.string(),
  },
  handler: async (ctx, args) => {
    return ctx.db
      .query("tasksProjection")
      .withIndex("by_task_id", (q) => q.eq("taskId", args.taskId))
      .first();
  },
});

/**
 * Get a list by ID
 */
export const getListById = internalQuery({
  args: {
    listId: v.string(),
  },
  handler: async (ctx, args) => {
    return ctx.db
      .query("taskListsProjection")
      .withIndex("by_list_id", (q) => q.eq("listId", args.listId))
      .first();
  },
});

/**
 * Get a tag by ID
 */
export const getTagById = internalQuery({
  args: {
    tagId: v.string(),
  },
  handler: async (ctx, args) => {
    return ctx.db
      .query("tagsProjection")
      .withIndex("by_tag_id", (q) => q.eq("tagId", args.tagId))
      .first();
  },
});

/**
 * Rebuild projections from events (for maintenance/recovery)
 */
export const rebuildProjections = internalMutation({
  args: {
    userId: v.string(),
    fromTimestamp: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const fromTime = args.fromTimestamp ?? 0;

    // Get all events for user after timestamp, ordered by timestamp
    const events = await ctx.db
      .query("events")
      .withIndex("by_user_timestamp", (q) =>
        q.eq("userId", args.userId).gte("timestamp", fromTime)
      )
      .collect();

    let processed = 0;
    let errors = 0;

    for (const event of events) {
      try {
        const eventType = event.eventType;

        if (eventType.startsWith("tasks.list.")) {
          await processListEvent(ctx, event as TaskEvent);
        } else if (eventType.startsWith("tasks.task.")) {
          await processTaskEvent(ctx, event as TaskEvent);
        } else if (eventType.startsWith("tasks.tag.")) {
          await processTagEvent(ctx, event as TaskEvent);
        }

        processed++;
      } catch (error) {
        console.error(`Error rebuilding from event ${event.eventId}:`, error);
        errors++;
      }
    }

    return {
      processed,
      errors,
      total: events.length,
    };
  },
});
