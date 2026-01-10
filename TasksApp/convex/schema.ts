import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

/**
 * Convex Schema for Orion Tasks App
 *
 * Architecture: Event Sourcing with Projections
 * - events: Append-only event log (source of truth)
 * - *Projection tables: Materialized views for efficient queries
 * - userConsent: Consent snapshots for GDPR/privacy compliance
 */

// Event payload validators for different event types
const taskEventPayload = v.object({
  taskId: v.string(),
  listId: v.optional(v.string()),
  title: v.optional(v.string()),
  notes: v.optional(v.string()),
  dueDate: v.optional(v.union(v.string(), v.null())),
  dueTime: v.optional(v.union(v.string(), v.null())),
  priority: v.optional(v.union(v.literal("none"), v.literal("low"), v.literal("medium"), v.literal("high"))),
  tags: v.optional(v.array(v.string())),
  flag: v.optional(v.boolean()),
  completed: v.optional(v.boolean()),
  completedAt: v.optional(v.union(v.string(), v.null())),
  redBeaconEnabled: v.optional(v.boolean()),
  mirrorToCalendar: v.optional(v.boolean()),
  calendarEventId: v.optional(v.union(v.string(), v.null())),
  recurrence: v.optional(v.union(v.object({
    frequency: v.union(v.literal("daily"), v.literal("weekly"), v.literal("monthly"), v.literal("yearly")),
    interval: v.number(),
    endDate: v.optional(v.string()),
    count: v.optional(v.number()),
    daysOfWeek: v.optional(v.array(v.number())),
  }), v.null())),
  subtasks: v.optional(v.array(v.object({
    id: v.string(),
    title: v.string(),
    completed: v.boolean(),
    sortOrder: v.number(),
  }))),
  attachments: v.optional(v.array(v.object({
    id: v.string(),
    type: v.union(v.literal("image"), v.literal("file"), v.literal("voice")),
    url: v.string(),
    name: v.optional(v.string()),
    size: v.optional(v.number()),
    mimeType: v.optional(v.string()),
  }))),
  location: v.optional(v.union(v.object({
    name: v.string(),
    address: v.optional(v.string()),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    radius: v.optional(v.number()),
    triggerOnEntry: v.optional(v.boolean()),
    triggerOnExit: v.optional(v.boolean()),
  }), v.null())),
  url: v.optional(v.union(v.string(), v.null())),
  sortOrder: v.optional(v.number()),
});

const listEventPayload = v.object({
  listId: v.string(),
  name: v.optional(v.string()),
  color: v.optional(v.string()),
  icon: v.optional(v.string()),
  sortOrder: v.optional(v.number()),
  smartList: v.optional(v.boolean()),
  smartListType: v.optional(v.union(
    v.literal("today"),
    v.literal("scheduled"),
    v.literal("flagged"),
    v.literal("all"),
    v.literal("completed")
  )),
});

const tagEventPayload = v.object({
  tagId: v.string(),
  name: v.optional(v.string()),
  color: v.optional(v.string()),
});

const voiceEventPayload = v.object({
  taskId: v.string(),
  voiceNoteId: v.string(),
  transcription: v.optional(v.string()),
  duration: v.optional(v.number()),
  language: v.optional(v.string()),
});

const aiEventPayload = v.object({
  taskId: v.optional(v.string()),
  suggestionId: v.optional(v.string()),
  suggestionType: v.optional(v.string()),
  suggestion: v.optional(v.any()),
  accepted: v.optional(v.boolean()),
  context: v.optional(v.any()),
});

// Generic event payload that can be any of the above
const eventPayload = v.union(
  taskEventPayload,
  listEventPayload,
  tagEventPayload,
  voiceEventPayload,
  aiEventPayload,
  v.object({}) // Empty payload for simple events
);

export default defineSchema({
  /**
   * Events Table (Append-Only Event Log)
   *
   * This is the source of truth for all state changes in the app.
   * Events are immutable once written.
   */
  events: defineTable({
    // Unique event identifier (UUID v7 for time-ordering)
    eventId: v.string(),

    // User who generated the event (from Clerk JWT)
    userId: v.string(),

    // Device that generated the event (for conflict resolution)
    deviceId: v.string(),

    // App identifier (for multi-app support)
    appId: v.string(),

    // Event timestamp (client-side, for ordering)
    timestamp: v.number(),

    // Server timestamp (for audit)
    serverTimestamp: v.number(),

    // Event type using dot notation (e.g., "tasks.task.created")
    eventType: v.string(),

    // Schema version for payload migration
    schemaVersion: v.number(),

    // Event payload (validated based on eventType)
    payload: v.any(),

    // References to media files (images, voice notes, etc.)
    mediaRefs: v.optional(v.array(v.object({
      id: v.string(),
      type: v.string(),
      storageId: v.optional(v.string()),
      url: v.optional(v.string()),
    }))),

    // Reference to consent snapshot at time of event
    consentSnapshotId: v.string(),

    // Processing status for Brain/AI features
    processingStatus: v.optional(v.union(
      v.literal("pending"),
      v.literal("queued"),
      v.literal("processing"),
      v.literal("completed"),
      v.literal("failed")
    )),

    // Error details if processing failed
    processingError: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    .index("by_user_timestamp", ["userId", "timestamp"])
    .index("by_user_type", ["userId", "eventType"])
    .index("by_event_id", ["eventId"])
    .index("by_processing_status", ["processingStatus"])
    .index("by_user_processing", ["userId", "processingStatus"]),

  /**
   * Task Lists Projection
   *
   * Materialized view of task lists derived from events.
   * Updated by the event projector.
   */
  taskListsProjection: defineTable({
    // List identifier (matches listId in events)
    listId: v.string(),

    // Owner user ID
    userId: v.string(),

    // Display name
    name: v.string(),

    // Color (hex or named color)
    color: v.string(),

    // SF Symbol name or custom icon
    icon: v.string(),

    // Sort order within user's lists
    sortOrder: v.number(),

    // Timestamps
    createdAt: v.number(),
    updatedAt: v.number(),

    // Soft delete flag
    tombstoned: v.boolean(),
    tombstonedAt: v.optional(v.number()),

    // Smart list configuration
    smartList: v.optional(v.boolean()),
    smartListType: v.optional(v.string()),

    // Task counts (denormalized for performance)
    taskCount: v.optional(v.number()),
    completedTaskCount: v.optional(v.number()),

    // Last event ID that updated this projection
    lastEventId: v.string(),
  })
    .index("by_user", ["userId"])
    .index("by_user_sort", ["userId", "sortOrder"])
    .index("by_list_id", ["listId"])
    .index("by_user_active", ["userId", "tombstoned"]),

  /**
   * Tasks Projection
   *
   * Materialized view of tasks derived from events.
   * Updated by the event projector.
   */
  tasksProjection: defineTable({
    // Task identifier (matches taskId in events)
    taskId: v.string(),

    // Owner user ID
    userId: v.string(),

    // Parent list ID
    listId: v.string(),

    // Task content
    title: v.string(),
    notes: v.optional(v.string()),

    // Due date/time (ISO strings)
    dueDate: v.optional(v.string()),
    dueTime: v.optional(v.string()),

    // Priority level
    priority: v.union(v.literal("none"), v.literal("low"), v.literal("medium"), v.literal("high")),

    // Tags (array of tag IDs)
    tags: v.array(v.string()),

    // Flagged status
    flag: v.boolean(),

    // Completion status
    completed: v.boolean(),
    completedAt: v.optional(v.string()),

    // Red Beacon feature
    redBeaconEnabled: v.boolean(),

    // Calendar integration
    mirrorToCalendar: v.boolean(),
    calendarEventId: v.optional(v.string()),

    // Recurrence configuration
    recurrence: v.optional(v.object({
      frequency: v.union(v.literal("daily"), v.literal("weekly"), v.literal("monthly"), v.literal("yearly")),
      interval: v.number(),
      endDate: v.optional(v.string()),
      count: v.optional(v.number()),
      daysOfWeek: v.optional(v.array(v.number())),
    })),

    // Subtasks
    subtasks: v.array(v.object({
      id: v.string(),
      title: v.string(),
      completed: v.boolean(),
      sortOrder: v.number(),
    })),

    // Attachments
    attachments: v.array(v.object({
      id: v.string(),
      type: v.union(v.literal("image"), v.literal("file"), v.literal("voice")),
      url: v.string(),
      name: v.optional(v.string()),
      size: v.optional(v.number()),
      mimeType: v.optional(v.string()),
    })),

    // Location-based reminder
    location: v.optional(v.object({
      name: v.string(),
      address: v.optional(v.string()),
      latitude: v.optional(v.number()),
      longitude: v.optional(v.number()),
      radius: v.optional(v.number()),
      triggerOnEntry: v.optional(v.boolean()),
      triggerOnExit: v.optional(v.boolean()),
    })),

    // URL attachment
    url: v.optional(v.string()),

    // Sort order within list
    sortOrder: v.number(),

    // Timestamps
    createdAt: v.number(),
    updatedAt: v.number(),

    // Soft delete flag
    tombstoned: v.boolean(),
    tombstonedAt: v.optional(v.number()),

    // Last event ID that updated this projection
    lastEventId: v.string(),
  })
    .index("by_user", ["userId"])
    .index("by_task_id", ["taskId"])
    .index("by_list", ["listId"])
    .index("by_user_list", ["userId", "listId"])
    .index("by_user_active", ["userId", "tombstoned"])
    .index("by_user_due_date", ["userId", "dueDate"])
    .index("by_user_flagged", ["userId", "flag"])
    .index("by_user_completed", ["userId", "completed"])
    .index("by_user_priority", ["userId", "priority"])
    .searchIndex("search_tasks", {
      searchField: "title",
      filterFields: ["userId", "listId", "completed", "tombstoned"],
    }),

  /**
   * Tags Projection
   *
   * Materialized view of tags derived from events.
   * Updated by the event projector.
   */
  tagsProjection: defineTable({
    // Tag identifier
    tagId: v.string(),

    // Owner user ID
    userId: v.string(),

    // Display name
    name: v.string(),

    // Color (hex or named color)
    color: v.string(),

    // Timestamps
    createdAt: v.number(),
    updatedAt: v.number(),

    // Soft delete flag
    tombstoned: v.boolean(),
    tombstonedAt: v.optional(v.number()),

    // Task count using this tag (denormalized)
    taskCount: v.optional(v.number()),

    // Last event ID that updated this projection
    lastEventId: v.string(),
  })
    .index("by_user", ["userId"])
    .index("by_tag_id", ["tagId"])
    .index("by_user_active", ["userId", "tombstoned"])
    .index("by_user_name", ["userId", "name"]),

  /**
   * User Consent Table
   *
   * Stores consent snapshots for GDPR/privacy compliance.
   * Referenced by events via consentSnapshotId.
   */
  userConsent: defineTable({
    // Consent snapshot identifier
    snapshotId: v.string(),

    // User ID
    userId: v.string(),

    // Full consent snapshot
    consentSnapshot: v.object({
      // Data processing consent
      dataProcessing: v.boolean(),

      // Analytics consent
      analytics: v.boolean(),

      // AI/Brain features consent
      aiFeatures: v.boolean(),

      // Voice transcription consent
      voiceTranscription: v.boolean(),

      // Cloud sync consent
      cloudSync: v.boolean(),

      // Third-party integrations consent
      thirdPartyIntegrations: v.boolean(),

      // Marketing consent
      marketing: v.optional(v.boolean()),

      // Consent version for legal tracking
      consentVersion: v.string(),

      // ISO country code for jurisdiction
      jurisdiction: v.optional(v.string()),

      // Age verification (for COPPA)
      ageVerified: v.optional(v.boolean()),
    }),

    // When consent was given/updated
    createdAt: v.number(),
    updatedAt: v.number(),

    // IP address hash (for audit, not PII)
    ipHash: v.optional(v.string()),

    // Device info (for audit)
    deviceInfo: v.optional(v.object({
      platform: v.string(),
      osVersion: v.optional(v.string()),
      appVersion: v.optional(v.string()),
    })),

    // Is this the current active consent?
    isActive: v.boolean(),
  })
    .index("by_user", ["userId"])
    .index("by_snapshot_id", ["snapshotId"])
    .index("by_user_active", ["userId", "isActive"]),

  /**
   * Brain Processing Queue
   *
   * Queue for events that need AI/Brain processing.
   * Used for async processing of voice transcriptions, suggestions, etc.
   */
  brainQueue: defineTable({
    // Event ID to process
    eventId: v.string(),

    // User ID
    userId: v.string(),

    // Event type (for routing)
    eventType: v.string(),

    // Processing priority (lower = higher priority)
    priority: v.number(),

    // Queue status
    status: v.union(
      v.literal("pending"),
      v.literal("processing"),
      v.literal("completed"),
      v.literal("failed"),
      v.literal("cancelled")
    ),

    // Retry count
    retryCount: v.number(),
    maxRetries: v.number(),

    // Timestamps
    createdAt: v.number(),
    startedAt: v.optional(v.number()),
    completedAt: v.optional(v.number()),

    // Error details
    errorMessage: v.optional(v.string()),
    errorStack: v.optional(v.string()),

    // Processing result (if any)
    result: v.optional(v.any()),
  })
    .index("by_status", ["status"])
    .index("by_user", ["userId"])
    .index("by_event_id", ["eventId"])
    .index("by_status_priority", ["status", "priority", "createdAt"]),

  /**
   * Sync State Table
   *
   * Tracks sync state per device for efficient delta sync.
   */
  syncState: defineTable({
    // User ID
    userId: v.string(),

    // Device ID
    deviceId: v.string(),

    // Last synced event timestamp
    lastSyncedTimestamp: v.number(),

    // Last synced event ID
    lastSyncedEventId: v.optional(v.string()),

    // Sync metadata
    lastSyncAt: v.number(),

    // Device info
    deviceInfo: v.optional(v.object({
      platform: v.string(),
      osVersion: v.optional(v.string()),
      appVersion: v.optional(v.string()),
      deviceName: v.optional(v.string()),
    })),
  })
    .index("by_user", ["userId"])
    .index("by_user_device", ["userId", "deviceId"]),
});
