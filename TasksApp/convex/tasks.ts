import { httpRouter } from "convex/server";
import { httpAction, internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import {
  authenticateRequest,
  createAuthErrorResponse,
  extractDeviceId,
  AuthResult,
  AuthError,
} from "./auth";

/**
 * Tasks App HTTP API
 *
 * This module defines the HTTP API for the Tasks App.
 * All endpoints require Clerk JWT authentication and consent verification.
 *
 * Endpoints:
 * - POST /api/events/batch - Insert batch of events
 * - GET /api/lists - Get all lists for user
 * - GET /api/lists/:listId/tasks - Get tasks for a list
 * - GET /api/tasks/smart/:viewType - Get tasks by smart view
 * - GET /api/tasks/search - Search tasks
 * - GET /api/tasks/:taskId - Get single task detail
 * - GET /api/tags - Get all tags for user
 */

// ============================================================================
// HTTP Router
// ============================================================================

const http = httpRouter();

// ============================================================================
// Event Ingestion
// ============================================================================

/**
 * POST /api/events/batch
 *
 * Insert a batch of events with JWT + consent verification.
 * Events are validated, stored, and processed asynchronously.
 */
http.route({
  path: "/api/events/batch",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    // Authenticate request
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;
    const deviceId = extractDeviceId(request, auth);

    try {
      // Parse request body
      const body = await request.json();
      const { events, consentSnapshotId } = body as {
        events: EventInput[];
        consentSnapshotId: string;
      };

      if (!events || !Array.isArray(events)) {
        return new Response(
          JSON.stringify({ error: "Invalid request: events array required" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      if (!consentSnapshotId) {
        return new Response(
          JSON.stringify({ error: "Invalid request: consentSnapshotId required" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Verify consent is valid
      const consentValid = await ctx.runQuery(internal.consent.verifyConsentSnapshot, {
        userId: auth.userId,
        snapshotId: consentSnapshotId,
      });

      if (!consentValid) {
        return new Response(
          JSON.stringify({ error: "Invalid or expired consent snapshot" }),
          { status: 403, headers: { "Content-Type": "application/json" } }
        );
      }

      // Process events in batch
      const result = await ctx.runMutation(internal.tasks.insertEventBatch, {
        userId: auth.userId,
        deviceId,
        appId: "com.orion.tasks",
        events,
        consentSnapshotId,
      });

      return new Response(
        JSON.stringify({
          success: true,
          processed: result.processed,
          failed: result.failed,
          eventIds: result.eventIds,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error processing event batch:", error);
      return new Response(
        JSON.stringify({
          error: "Failed to process events",
          details: error instanceof Error ? error.message : "Unknown error",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

// ============================================================================
// List Queries
// ============================================================================

/**
 * GET /api/lists
 *
 * Get all lists for the authenticated user.
 */
http.route({
  path: "/api/lists",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;

    try {
      const lists = await ctx.runQuery(internal.tasks.queryListsForUser, {
        userId: auth.userId,
        includeSmartLists: true,
      });

      return new Response(
        JSON.stringify({ lists }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error fetching lists:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch lists" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

// ============================================================================
// Task Queries
// ============================================================================

/**
 * GET /api/lists/:listId/tasks
 *
 * Get tasks for a specific list.
 */
http.route({
  path: "/api/lists/:listId/tasks",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;

    // Extract listId from URL
    const url = new URL(request.url);
    const pathParts = url.pathname.split("/");
    const listIdIndex = pathParts.indexOf("lists") + 1;
    const listId = pathParts[listIdIndex];

    if (!listId) {
      return new Response(
        JSON.stringify({ error: "List ID required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Parse query parameters
    const includeCompleted = url.searchParams.get("includeCompleted") !== "false";
    const limit = parseInt(url.searchParams.get("limit") ?? "100", 10);
    const cursor = url.searchParams.get("cursor") ?? undefined;

    try {
      const result = await ctx.runQuery(internal.tasks.queryTasksByList, {
        userId: auth.userId,
        listId,
        includeCompleted,
        limit,
        cursor,
      });

      return new Response(
        JSON.stringify(result),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error fetching tasks:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch tasks" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

/**
 * GET /api/tasks/smart/:viewType
 *
 * Get tasks by smart view (today, scheduled, flagged, completed, all).
 */
http.route({
  path: "/api/tasks/smart/:viewType",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;

    // Extract viewType from URL
    const url = new URL(request.url);
    const pathParts = url.pathname.split("/");
    const viewType = pathParts[pathParts.length - 1] as SmartViewType;

    const validViewTypes = ["today", "scheduled", "flagged", "completed", "all"];
    if (!validViewTypes.includes(viewType)) {
      return new Response(
        JSON.stringify({ error: `Invalid view type: ${viewType}` }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Parse query parameters
    const limit = parseInt(url.searchParams.get("limit") ?? "100", 10);
    const cursor = url.searchParams.get("cursor") ?? undefined;

    try {
      const result = await ctx.runQuery(internal.tasks.querySmartView, {
        userId: auth.userId,
        viewType,
        limit,
        cursor,
      });

      return new Response(
        JSON.stringify(result),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error fetching smart view:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch tasks" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

/**
 * GET /api/tasks/search
 *
 * Search tasks by query string.
 */
http.route({
  path: "/api/tasks/search",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;
    const url = new URL(request.url);

    const query = url.searchParams.get("q");
    if (!query) {
      return new Response(
        JSON.stringify({ error: "Search query required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const listId = url.searchParams.get("listId") ?? undefined;
    const includeCompleted = url.searchParams.get("includeCompleted") !== "false";
    const limit = parseInt(url.searchParams.get("limit") ?? "50", 10);

    try {
      const result = await ctx.runQuery(internal.tasks.querySearch, {
        userId: auth.userId,
        query,
        listId,
        includeCompleted,
        limit,
      });

      return new Response(
        JSON.stringify(result),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error searching tasks:", error);
      return new Response(
        JSON.stringify({ error: "Failed to search tasks" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

/**
 * GET /api/tasks/:taskId
 *
 * Get a single task by ID.
 */
http.route({
  path: "/api/tasks/:taskId",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;

    // Extract taskId from URL
    const url = new URL(request.url);
    const pathParts = url.pathname.split("/");
    const taskId = pathParts[pathParts.length - 1];

    if (!taskId) {
      return new Response(
        JSON.stringify({ error: "Task ID required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    try {
      const task = await ctx.runQuery(internal.tasks.queryTaskDetail, {
        userId: auth.userId,
        taskId,
      });

      if (!task) {
        return new Response(
          JSON.stringify({ error: "Task not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ task }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error fetching task:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch task" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

// ============================================================================
// Tag Queries
// ============================================================================

/**
 * GET /api/tags
 *
 * Get all tags for the authenticated user.
 */
http.route({
  path: "/api/tags",
  method: "GET",
  handler: httpAction(async (ctx, request) => {
    const authResult = await authenticateRequest(request, ctx);
    if (!authResult.success) {
      return createAuthErrorResponse(authResult as AuthError);
    }

    const auth = authResult as AuthResult;

    try {
      const tags = await ctx.runQuery(internal.tasks.queryTagsForUser, {
        userId: auth.userId,
      });

      return new Response(
        JSON.stringify({ tags }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (error) {
      console.error("Error fetching tags:", error);
      return new Response(
        JSON.stringify({ error: "Failed to fetch tags" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }),
});

// ============================================================================
// Internal Mutations
// ============================================================================

interface EventInput {
  eventId: string;
  timestamp: number;
  eventType: string;
  schemaVersion: number;
  payload: any;
  mediaRefs?: any[];
}

type SmartViewType = "today" | "scheduled" | "flagged" | "completed" | "all";

/**
 * Insert a batch of events
 */
export const insertEventBatch = internalMutation({
  args: {
    userId: v.string(),
    deviceId: v.string(),
    appId: v.string(),
    events: v.array(v.object({
      eventId: v.string(),
      timestamp: v.number(),
      eventType: v.string(),
      schemaVersion: v.number(),
      payload: v.any(),
      mediaRefs: v.optional(v.array(v.any())),
    })),
    consentSnapshotId: v.string(),
  },
  handler: async (ctx, args) => {
    const serverTimestamp = Date.now();
    const eventIds: string[] = [];
    let processed = 0;
    let failed = 0;

    for (const event of args.events) {
      try {
        // Check for duplicate event ID (idempotency)
        const existing = await ctx.db
          .query("events")
          .withIndex("by_event_id", (q) => q.eq("eventId", event.eventId))
          .first();

        if (existing) {
          // Event already exists - skip but count as processed
          eventIds.push(event.eventId);
          processed++;
          continue;
        }

        // Insert the event
        const id = await ctx.db.insert("events", {
          eventId: event.eventId,
          userId: args.userId,
          deviceId: args.deviceId,
          appId: args.appId,
          timestamp: event.timestamp,
          serverTimestamp,
          eventType: event.eventType,
          schemaVersion: event.schemaVersion,
          payload: event.payload,
          mediaRefs: event.mediaRefs,
          consentSnapshotId: args.consentSnapshotId,
          processingStatus: "pending",
        });

        eventIds.push(event.eventId);

        // Process the event to update projections
        await ctx.scheduler.runAfter(0, internal.projections.processEvent, {
          eventId: id,
        });

        // Check if this event should trigger Brain processing
        await ctx.scheduler.runAfter(0, internal.brainRegistry.checkAndQueueEvent, {
          eventId: id,
          eventType: event.eventType,
          userId: args.userId,
        });

        processed++;
      } catch (error) {
        console.error(`Error inserting event ${event.eventId}:`, error);
        failed++;
      }
    }

    return { processed, failed, eventIds };
  },
});

// ============================================================================
// Internal Queries
// ============================================================================

/**
 * Query lists for a user
 */
export const queryListsForUser = internalQuery({
  args: {
    userId: v.string(),
    includeSmartLists: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const lists = await ctx.db
      .query("taskListsProjection")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("tombstoned", false)
      )
      .collect();

    // Sort by sortOrder
    return lists.sort((a, b) => a.sortOrder - b.sortOrder);
  },
});

/**
 * Query tasks by list
 */
export const queryTasksByList = internalQuery({
  args: {
    userId: v.string(),
    listId: v.string(),
    includeCompleted: v.optional(v.boolean()),
    limit: v.optional(v.number()),
    cursor: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 100;

    let query = ctx.db
      .query("tasksProjection")
      .withIndex("by_user_list", (q) =>
        q.eq("userId", args.userId).eq("listId", args.listId)
      );

    const allTasks = await query.collect();

    // Filter tombstoned and optionally completed tasks
    let tasks = allTasks.filter((t) => !t.tombstoned);
    if (!args.includeCompleted) {
      tasks = tasks.filter((t) => !t.completed);
    }

    // Sort by sortOrder, then by createdAt
    tasks.sort((a, b) => {
      if (a.sortOrder !== b.sortOrder) {
        return a.sortOrder - b.sortOrder;
      }
      return a.createdAt - b.createdAt;
    });

    // Apply pagination
    const startIndex = args.cursor ? tasks.findIndex((t) => t.taskId === args.cursor) + 1 : 0;
    const pageTasks = tasks.slice(startIndex, startIndex + limit);
    const nextCursor = pageTasks.length === limit ? pageTasks[pageTasks.length - 1].taskId : undefined;

    return {
      tasks: pageTasks,
      nextCursor,
      totalCount: tasks.length,
    };
  },
});

/**
 * Query tasks by smart view
 */
export const querySmartView = internalQuery({
  args: {
    userId: v.string(),
    viewType: v.union(
      v.literal("today"),
      v.literal("scheduled"),
      v.literal("flagged"),
      v.literal("completed"),
      v.literal("all")
    ),
    limit: v.optional(v.number()),
    cursor: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 100;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStr = today.toISOString().split("T")[0];

    // Get all non-tombstoned tasks for user
    const allTasks = await ctx.db
      .query("tasksProjection")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("tombstoned", false)
      )
      .collect();

    let tasks: typeof allTasks = [];

    switch (args.viewType) {
      case "today":
        tasks = allTasks.filter((t) => {
          if (t.completed) return false;
          if (!t.dueDate) return false;
          return t.dueDate.startsWith(todayStr);
        });
        // Sort by due time, then priority
        tasks.sort((a, b) => {
          if (a.dueTime && b.dueTime) {
            return a.dueTime.localeCompare(b.dueTime);
          }
          if (a.dueTime) return -1;
          if (b.dueTime) return 1;
          return getPriorityValue(b.priority) - getPriorityValue(a.priority);
        });
        break;

      case "scheduled":
        tasks = allTasks.filter((t) => !t.completed && t.dueDate);
        // Sort by due date
        tasks.sort((a, b) => {
          if (!a.dueDate) return 1;
          if (!b.dueDate) return -1;
          return a.dueDate.localeCompare(b.dueDate);
        });
        break;

      case "flagged":
        tasks = allTasks.filter((t) => !t.completed && t.flag);
        // Sort by due date, then priority
        tasks.sort((a, b) => {
          if (a.dueDate && b.dueDate) {
            const dateCompare = a.dueDate.localeCompare(b.dueDate);
            if (dateCompare !== 0) return dateCompare;
          }
          if (a.dueDate) return -1;
          if (b.dueDate) return 1;
          return getPriorityValue(b.priority) - getPriorityValue(a.priority);
        });
        break;

      case "completed":
        tasks = allTasks.filter((t) => t.completed);
        // Sort by completion date, newest first
        tasks.sort((a, b) => {
          if (a.completedAt && b.completedAt) {
            return b.completedAt.localeCompare(a.completedAt);
          }
          return b.updatedAt - a.updatedAt;
        });
        break;

      case "all":
        tasks = allTasks.filter((t) => !t.completed);
        // Sort by due date, then priority, then created
        tasks.sort((a, b) => {
          if (a.dueDate && b.dueDate) {
            const dateCompare = a.dueDate.localeCompare(b.dueDate);
            if (dateCompare !== 0) return dateCompare;
          }
          if (a.dueDate) return -1;
          if (b.dueDate) return 1;
          const priorityCompare = getPriorityValue(b.priority) - getPriorityValue(a.priority);
          if (priorityCompare !== 0) return priorityCompare;
          return a.createdAt - b.createdAt;
        });
        break;
    }

    // Apply pagination
    const startIndex = args.cursor ? tasks.findIndex((t) => t.taskId === args.cursor) + 1 : 0;
    const pageTasks = tasks.slice(startIndex, startIndex + limit);
    const nextCursor = pageTasks.length === limit ? pageTasks[pageTasks.length - 1].taskId : undefined;

    return {
      tasks: pageTasks,
      nextCursor,
      totalCount: tasks.length,
    };
  },
});

function getPriorityValue(priority: string): number {
  switch (priority) {
    case "high":
      return 3;
    case "medium":
      return 2;
    case "low":
      return 1;
    default:
      return 0;
  }
}

/**
 * Search tasks
 */
export const querySearch = internalQuery({
  args: {
    userId: v.string(),
    query: v.string(),
    listId: v.optional(v.string()),
    includeCompleted: v.optional(v.boolean()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;

    // Use the search index
    let searchQuery = ctx.db
      .query("tasksProjection")
      .withSearchIndex("search_tasks", (q) => {
        let query = q.search("title", args.query).eq("userId", args.userId).eq("tombstoned", false);
        if (args.listId) {
          query = query.eq("listId", args.listId);
        }
        if (!args.includeCompleted) {
          query = query.eq("completed", false);
        }
        return query;
      });

    const tasks = await searchQuery.take(limit);

    return {
      tasks,
      totalCount: tasks.length,
    };
  },
});

/**
 * Get single task detail
 */
export const queryTaskDetail = internalQuery({
  args: {
    userId: v.string(),
    taskId: v.string(),
  },
  handler: async (ctx, args) => {
    const task = await ctx.db
      .query("tasksProjection")
      .withIndex("by_task_id", (q) => q.eq("taskId", args.taskId))
      .first();

    if (!task) {
      return null;
    }

    // Verify ownership
    if (task.userId !== args.userId) {
      return null;
    }

    // Don't return tombstoned tasks
    if (task.tombstoned) {
      return null;
    }

    return task;
  },
});

/**
 * Query tags for a user
 */
export const queryTagsForUser = internalQuery({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const tags = await ctx.db
      .query("tagsProjection")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("tombstoned", false)
      )
      .collect();

    // Sort by name
    return tags.sort((a, b) => a.name.localeCompare(b.name));
  },
});

// Export the HTTP router
export default http;
