import { internalMutation, internalQuery, internalAction } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { internal } from "./_generated/api";

/**
 * Brain Event Registry
 *
 * This module manages the registration of event types that trigger Brain/AI processing.
 * It provides a centralized registry for routing events to appropriate AI handlers.
 *
 * Event Types That Trigger Brain Processing:
 * - tasks.voice.transcribed: Voice note needs transcription processing
 * - tasks.ai.suggestion.requested: User requested AI suggestion
 * - tasks.ai.suggestion.generated: AI generated a suggestion
 * - tasks.task.created: New task may benefit from AI enrichment
 * - tasks.natural.input: Natural language input needs parsing
 */

// ============================================================================
// Types
// ============================================================================

/**
 * Brain event handler configuration
 */
interface BrainEventHandler {
  // Event type pattern (supports wildcards with *)
  eventType: string;

  // Handler name for routing
  handler: BrainHandlerType;

  // Priority (lower = higher priority)
  priority: number;

  // Required consent for this handler
  requiredConsent: string[];

  // Whether to process immediately or queue
  async: boolean;

  // Maximum retries on failure
  maxRetries: number;

  // Delay between retries (ms)
  retryDelayMs: number;

  // Optional condition for when to trigger
  condition?: (payload: any) => boolean;
}

type BrainHandlerType =
  | "voice_transcription"
  | "natural_language_parse"
  | "task_enrichment"
  | "smart_suggestion"
  | "due_date_inference"
  | "priority_inference"
  | "tag_suggestion"
  | "list_suggestion"
  | "calendar_sync";

// ============================================================================
// Event Registry
// ============================================================================

/**
 * Registry of events that trigger Brain processing
 */
const BRAIN_EVENT_REGISTRY: BrainEventHandler[] = [
  // Voice transcription events
  {
    eventType: "tasks.voice.recorded",
    handler: "voice_transcription",
    priority: 1,
    requiredConsent: ["aiFeatures", "voiceTranscription"],
    async: true,
    maxRetries: 3,
    retryDelayMs: 5000,
  },
  {
    eventType: "tasks.voice.transcribed",
    handler: "natural_language_parse",
    priority: 2,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 3,
    retryDelayMs: 3000,
  },

  // Natural language input
  {
    eventType: "tasks.natural.input",
    handler: "natural_language_parse",
    priority: 1,
    requiredConsent: ["aiFeatures"],
    async: false,
    maxRetries: 2,
    retryDelayMs: 2000,
  },

  // Task creation for AI enrichment
  {
    eventType: "tasks.task.created",
    handler: "task_enrichment",
    priority: 5,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 2,
    retryDelayMs: 5000,
    condition: (payload) => {
      // Only enrich if task has minimal info
      return payload.title && !payload.dueDate && !payload.priority;
    },
  },

  // Explicit AI suggestion requests
  {
    eventType: "tasks.ai.suggestion.requested",
    handler: "smart_suggestion",
    priority: 1,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 3,
    retryDelayMs: 3000,
  },

  // Due date inference
  {
    eventType: "tasks.ai.duedate.requested",
    handler: "due_date_inference",
    priority: 2,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 2,
    retryDelayMs: 2000,
  },

  // Priority inference
  {
    eventType: "tasks.ai.priority.requested",
    handler: "priority_inference",
    priority: 2,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 2,
    retryDelayMs: 2000,
  },

  // Tag suggestions
  {
    eventType: "tasks.ai.tags.requested",
    handler: "tag_suggestion",
    priority: 3,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 2,
    retryDelayMs: 2000,
  },

  // List suggestions
  {
    eventType: "tasks.ai.list.requested",
    handler: "list_suggestion",
    priority: 3,
    requiredConsent: ["aiFeatures"],
    async: true,
    maxRetries: 2,
    retryDelayMs: 2000,
  },

  // Calendar sync events
  {
    eventType: "tasks.calendar.sync.requested",
    handler: "calendar_sync",
    priority: 4,
    requiredConsent: ["thirdPartyIntegrations"],
    async: true,
    maxRetries: 3,
    retryDelayMs: 10000,
  },
];

// ============================================================================
// Registry Functions
// ============================================================================

/**
 * Find matching handlers for an event type
 */
function findMatchingHandlers(eventType: string): BrainEventHandler[] {
  return BRAIN_EVENT_REGISTRY.filter((handler) => {
    if (handler.eventType === eventType) {
      return true;
    }

    // Support wildcard matching (e.g., "tasks.ai.*")
    if (handler.eventType.endsWith("*")) {
      const prefix = handler.eventType.slice(0, -1);
      return eventType.startsWith(prefix);
    }

    return false;
  }).sort((a, b) => a.priority - b.priority);
}

/**
 * Check if an event type triggers Brain processing
 */
export function shouldTriggerBrain(eventType: string): boolean {
  return findMatchingHandlers(eventType).length > 0;
}

/**
 * Get handler configuration for an event type
 */
export function getHandlerConfig(eventType: string): BrainEventHandler | null {
  const handlers = findMatchingHandlers(eventType);
  return handlers.length > 0 ? handlers[0] : null;
}

// ============================================================================
// Internal Mutations
// ============================================================================

/**
 * Check if an event should trigger Brain processing and queue it
 */
export const checkAndQueueEvent = internalMutation({
  args: {
    eventId: v.id("events"),
    eventType: v.string(),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const handlers = findMatchingHandlers(args.eventType);

    if (handlers.length === 0) {
      return { queued: false, reason: "No matching handlers" };
    }

    const event = await ctx.db.get(args.eventId);
    if (!event) {
      return { queued: false, reason: "Event not found" };
    }

    // Get user's consent
    const consent = await ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();

    if (!consent) {
      return { queued: false, reason: "No active consent" };
    }

    // Process each matching handler
    const queuedHandlers: string[] = [];

    for (const handler of handlers) {
      // Check consent requirements
      const hasConsent = handler.requiredConsent.every((req) => {
        const consentValue = consent.consentSnapshot[req as keyof typeof consent.consentSnapshot];
        return consentValue === true;
      });

      if (!hasConsent) {
        continue;
      }

      // Check condition if present
      if (handler.condition && !handler.condition(event.payload)) {
        continue;
      }

      // Queue the event for processing
      await ctx.db.insert("brainQueue", {
        eventId: args.eventId.toString(),
        userId: args.userId,
        eventType: args.eventType,
        priority: handler.priority,
        status: "pending",
        retryCount: 0,
        maxRetries: handler.maxRetries,
        createdAt: Date.now(),
      });

      queuedHandlers.push(handler.handler);

      // Update event processing status
      await ctx.db.patch(args.eventId, {
        processingStatus: "queued",
      });

      // If handler is sync, trigger immediate processing
      if (!handler.async) {
        await ctx.scheduler.runAfter(0, internal.brainRegistry.processQueueItem, {
          eventId: args.eventId,
          handler: handler.handler,
        });
      }
    }

    return {
      queued: queuedHandlers.length > 0,
      handlers: queuedHandlers,
    };
  },
});

/**
 * Process a queued Brain item
 */
export const processQueueItem = internalMutation({
  args: {
    eventId: v.id("events"),
    handler: v.string(),
  },
  handler: async (ctx, args) => {
    const event = await ctx.db.get(args.eventId);
    if (!event) {
      return { success: false, error: "Event not found" };
    }

    // Find the queue item
    const queueItem = await ctx.db
      .query("brainQueue")
      .withIndex("by_event_id", (q) => q.eq("eventId", args.eventId.toString()))
      .first();

    if (!queueItem) {
      return { success: false, error: "Queue item not found" };
    }

    // Update status to processing
    await ctx.db.patch(queueItem._id, {
      status: "processing",
      startedAt: Date.now(),
    });

    await ctx.db.patch(args.eventId, {
      processingStatus: "processing",
    });

    // Schedule the actual processing action
    await ctx.scheduler.runAfter(0, internal.brainRegistry.executeBrainHandler, {
      queueItemId: queueItem._id,
      eventId: args.eventId,
      handler: args.handler as BrainHandlerType,
      payload: event.payload,
      userId: event.userId,
    });

    return { success: true };
  },
});

/**
 * Execute a Brain handler
 */
export const executeBrainHandler = internalAction({
  args: {
    queueItemId: v.id("brainQueue"),
    eventId: v.id("events"),
    handler: v.string(),
    payload: v.any(),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    try {
      let result: any;

      // Route to appropriate handler
      switch (args.handler as BrainHandlerType) {
        case "voice_transcription":
          result = await handleVoiceTranscription(ctx, args.payload, args.userId);
          break;

        case "natural_language_parse":
          result = await handleNaturalLanguageParse(ctx, args.payload, args.userId);
          break;

        case "task_enrichment":
          result = await handleTaskEnrichment(ctx, args.payload, args.userId);
          break;

        case "smart_suggestion":
          result = await handleSmartSuggestion(ctx, args.payload, args.userId);
          break;

        case "due_date_inference":
          result = await handleDueDateInference(ctx, args.payload, args.userId);
          break;

        case "priority_inference":
          result = await handlePriorityInference(ctx, args.payload, args.userId);
          break;

        case "tag_suggestion":
          result = await handleTagSuggestion(ctx, args.payload, args.userId);
          break;

        case "list_suggestion":
          result = await handleListSuggestion(ctx, args.payload, args.userId);
          break;

        case "calendar_sync":
          result = await handleCalendarSync(ctx, args.payload, args.userId);
          break;

        default:
          throw new Error(`Unknown handler: ${args.handler}`);
      }

      // Mark as completed
      await ctx.runMutation(internal.brainRegistry.markQueueItemCompleted, {
        queueItemId: args.queueItemId,
        eventId: args.eventId,
        result,
      });

      return { success: true, result };
    } catch (error) {
      console.error(`Brain handler error (${args.handler}):`, error);

      // Handle failure
      await ctx.runMutation(internal.brainRegistry.markQueueItemFailed, {
        queueItemId: args.queueItemId,
        eventId: args.eventId,
        error: error instanceof Error ? error.message : "Unknown error",
      });

      return { success: false, error: String(error) };
    }
  },
});

/**
 * Mark a queue item as completed
 */
export const markQueueItemCompleted = internalMutation({
  args: {
    queueItemId: v.id("brainQueue"),
    eventId: v.id("events"),
    result: v.optional(v.any()),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.queueItemId, {
      status: "completed",
      completedAt: Date.now(),
      result: args.result,
    });

    await ctx.db.patch(args.eventId, {
      processingStatus: "completed",
    });
  },
});

/**
 * Mark a queue item as failed
 */
export const markQueueItemFailed = internalMutation({
  args: {
    queueItemId: v.id("brainQueue"),
    eventId: v.id("events"),
    error: v.string(),
  },
  handler: async (ctx, args) => {
    const queueItem = await ctx.db.get(args.queueItemId);
    if (!queueItem) {
      return;
    }

    const newRetryCount = queueItem.retryCount + 1;

    if (newRetryCount >= queueItem.maxRetries) {
      // Max retries reached - mark as failed
      await ctx.db.patch(args.queueItemId, {
        status: "failed",
        completedAt: Date.now(),
        errorMessage: args.error,
        retryCount: newRetryCount,
      });

      await ctx.db.patch(args.eventId, {
        processingStatus: "failed",
        processingError: args.error,
      });
    } else {
      // Schedule retry
      await ctx.db.patch(args.queueItemId, {
        status: "pending",
        retryCount: newRetryCount,
        errorMessage: args.error,
      });

      await ctx.db.patch(args.eventId, {
        processingStatus: "pending",
      });

      // Get handler config for retry delay
      const handler = getHandlerConfig(queueItem.eventType);
      const delay = handler?.retryDelayMs ?? 5000;

      await ctx.scheduler.runAfter(delay, internal.brainRegistry.processQueueItem, {
        eventId: args.eventId,
        handler: queueItem.eventType,
      });
    }
  },
});

/**
 * Process pending queue items (batch processor)
 */
export const processPendingQueue = internalMutation({
  args: {
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;

    const pendingItems = await ctx.db
      .query("brainQueue")
      .withIndex("by_status_priority", (q) => q.eq("status", "pending"))
      .take(limit);

    for (const item of pendingItems) {
      const handler = getHandlerConfig(item.eventType);
      if (handler) {
        await ctx.scheduler.runAfter(0, internal.brainRegistry.processQueueItem, {
          eventId: item.eventId as unknown as Id<"events">,
          handler: handler.handler,
        });
      }
    }

    return { processed: pendingItems.length };
  },
});

/**
 * Get queue status for a user
 */
export const getQueueStatus = internalQuery({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const items = await ctx.db
      .query("brainQueue")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect();

    const pending = items.filter((i) => i.status === "pending").length;
    const processing = items.filter((i) => i.status === "processing").length;
    const completed = items.filter((i) => i.status === "completed").length;
    const failed = items.filter((i) => i.status === "failed").length;

    return {
      pending,
      processing,
      completed,
      failed,
      total: items.length,
    };
  },
});

// ============================================================================
// Brain Handler Implementations
// ============================================================================

/**
 * Handle voice transcription
 */
async function handleVoiceTranscription(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  // This would integrate with a speech-to-text service (e.g., Whisper API)
  // For now, return a placeholder

  const { voiceNoteId, taskId } = payload;

  // In production, this would:
  // 1. Fetch the audio file from storage
  // 2. Send to transcription API
  // 3. Return the transcription

  return {
    voiceNoteId,
    taskId,
    status: "transcription_pending",
    message: "Voice transcription service integration pending",
  };
}

/**
 * Handle natural language parsing
 */
async function handleNaturalLanguageParse(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  // This would integrate with an NLP service to parse natural language input
  // For now, return a placeholder

  const { text, taskId } = payload;

  // In production, this would:
  // 1. Parse the text for dates, times, priorities
  // 2. Extract entities (projects, tags, people)
  // 3. Return structured task data

  return {
    taskId,
    parsedText: text,
    status: "nlp_pending",
    message: "NLP service integration pending",
  };
}

/**
 * Handle task enrichment
 */
async function handleTaskEnrichment(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  // This would use AI to suggest improvements to a task
  const { taskId, title } = payload;

  // In production, this would:
  // 1. Analyze the task title and notes
  // 2. Suggest due dates, priorities, tags
  // 3. Return enrichment suggestions

  return {
    taskId,
    suggestions: [],
    status: "enrichment_pending",
    message: "AI enrichment service integration pending",
  };
}

/**
 * Handle smart suggestion
 */
async function handleSmartSuggestion(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  // This would generate AI-powered suggestions
  const { suggestionType, context } = payload;

  return {
    suggestionType,
    suggestions: [],
    status: "suggestion_pending",
    message: "Smart suggestion service integration pending",
  };
}

/**
 * Handle due date inference
 */
async function handleDueDateInference(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  const { taskId, title, notes } = payload;

  // In production, this would:
  // 1. Analyze text for temporal references
  // 2. Consider user's patterns
  // 3. Return suggested due date

  return {
    taskId,
    suggestedDueDate: null,
    confidence: 0,
    status: "inference_pending",
    message: "Due date inference service integration pending",
  };
}

/**
 * Handle priority inference
 */
async function handlePriorityInference(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  const { taskId, title, notes } = payload;

  // In production, this would:
  // 1. Analyze urgency indicators in text
  // 2. Consider user's task history
  // 3. Return suggested priority

  return {
    taskId,
    suggestedPriority: "none",
    confidence: 0,
    status: "inference_pending",
    message: "Priority inference service integration pending",
  };
}

/**
 * Handle tag suggestion
 */
async function handleTagSuggestion(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  const { taskId, title, notes } = payload;

  // In production, this would:
  // 1. Analyze task content
  // 2. Match against existing tags
  // 3. Suggest new or existing tags

  return {
    taskId,
    suggestedTags: [],
    status: "suggestion_pending",
    message: "Tag suggestion service integration pending",
  };
}

/**
 * Handle list suggestion
 */
async function handleListSuggestion(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  const { taskId, title, notes } = payload;

  // In production, this would:
  // 1. Analyze task content
  // 2. Match against existing lists
  // 3. Suggest appropriate list

  return {
    taskId,
    suggestedListId: null,
    confidence: 0,
    status: "suggestion_pending",
    message: "List suggestion service integration pending",
  };
}

/**
 * Handle calendar sync
 */
async function handleCalendarSync(
  ctx: any,
  payload: any,
  userId: string
): Promise<any> {
  const { taskId, calendarProvider } = payload;

  // In production, this would:
  // 1. Connect to calendar API (Google, Apple, etc.)
  // 2. Create or update calendar event
  // 3. Return sync status

  return {
    taskId,
    calendarEventId: null,
    status: "sync_pending",
    message: "Calendar sync service integration pending",
  };
}

// ============================================================================
// Exports
// ============================================================================

export const registry = {
  shouldTriggerBrain,
  getHandlerConfig,
  eventTypes: BRAIN_EVENT_REGISTRY.map((h) => h.eventType),
};
