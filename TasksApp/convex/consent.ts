import { internalMutation, internalQuery } from "./_generated/server";
import { v } from "convex/values";

/**
 * Consent Management Module
 *
 * This module handles user consent operations for GDPR/privacy compliance.
 * It manages consent snapshots that are referenced by events.
 */

// ============================================================================
// Types
// ============================================================================

export interface ConsentSnapshot {
  dataProcessing: boolean;
  analytics: boolean;
  aiFeatures: boolean;
  voiceTranscription: boolean;
  cloudSync: boolean;
  thirdPartyIntegrations: boolean;
  marketing?: boolean;
  consentVersion: string;
  jurisdiction?: string;
  ageVerified?: boolean;
}

// ============================================================================
// Internal Queries
// ============================================================================

/**
 * Get the active consent for a user
 */
export const getActiveConsent = internalQuery({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    return ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();
  },
});

/**
 * Verify a consent snapshot is valid for a user
 */
export const verifyConsentSnapshot = internalQuery({
  args: {
    userId: v.string(),
    snapshotId: v.string(),
  },
  handler: async (ctx, args) => {
    const consent = await ctx.db
      .query("userConsent")
      .withIndex("by_snapshot_id", (q) => q.eq("snapshotId", args.snapshotId))
      .first();

    if (!consent) {
      return false;
    }

    // Verify the consent belongs to the user
    if (consent.userId !== args.userId) {
      return false;
    }

    return true;
  },
});

/**
 * Get consent history for a user
 */
export const getConsentHistory = internalQuery({
  args: {
    userId: v.string(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;

    return ctx.db
      .query("userConsent")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(limit);
  },
});

/**
 * Check if user has specific consent
 */
export const hasConsent = internalQuery({
  args: {
    userId: v.string(),
    consentType: v.string(),
  },
  handler: async (ctx, args) => {
    const activeConsent = await ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();

    if (!activeConsent) {
      return false;
    }

    const snapshot = activeConsent.consentSnapshot;
    return snapshot[args.consentType as keyof typeof snapshot] === true;
  },
});

// ============================================================================
// Internal Mutations
// ============================================================================

/**
 * Create or update user consent
 */
export const upsertConsent = internalMutation({
  args: {
    userId: v.string(),
    consentSnapshot: v.object({
      dataProcessing: v.boolean(),
      analytics: v.boolean(),
      aiFeatures: v.boolean(),
      voiceTranscription: v.boolean(),
      cloudSync: v.boolean(),
      thirdPartyIntegrations: v.boolean(),
      marketing: v.optional(v.boolean()),
      consentVersion: v.string(),
      jurisdiction: v.optional(v.string()),
      ageVerified: v.optional(v.boolean()),
    }),
    deviceInfo: v.optional(v.object({
      platform: v.string(),
      osVersion: v.optional(v.string()),
      appVersion: v.optional(v.string()),
    })),
    ipHash: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const snapshotId = generateSnapshotId();

    // Deactivate any existing active consent
    const existingConsent = await ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();

    if (existingConsent) {
      await ctx.db.patch(existingConsent._id, {
        isActive: false,
        updatedAt: now,
      });
    }

    // Create new consent record
    const id = await ctx.db.insert("userConsent", {
      snapshotId,
      userId: args.userId,
      consentSnapshot: args.consentSnapshot,
      deviceInfo: args.deviceInfo,
      ipHash: args.ipHash,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    });

    return { id, snapshotId };
  },
});

/**
 * Revoke all consent for a user
 */
export const revokeConsent = internalMutation({
  args: {
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Find and deactivate active consent
    const activeConsent = await ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();

    if (activeConsent) {
      await ctx.db.patch(activeConsent._id, {
        isActive: false,
        updatedAt: now,
      });
    }

    // Create a revocation record (all false)
    const snapshotId = generateSnapshotId();
    await ctx.db.insert("userConsent", {
      snapshotId,
      userId: args.userId,
      consentSnapshot: {
        dataProcessing: false,
        analytics: false,
        aiFeatures: false,
        voiceTranscription: false,
        cloudSync: false,
        thirdPartyIntegrations: false,
        marketing: false,
        consentVersion: "1.0",
      },
      createdAt: now,
      updatedAt: now,
      isActive: true,
    });

    return { revoked: true, snapshotId };
  },
});

/**
 * Update specific consent fields
 */
export const updateConsent = internalMutation({
  args: {
    userId: v.string(),
    updates: v.object({
      dataProcessing: v.optional(v.boolean()),
      analytics: v.optional(v.boolean()),
      aiFeatures: v.optional(v.boolean()),
      voiceTranscription: v.optional(v.boolean()),
      cloudSync: v.optional(v.boolean()),
      thirdPartyIntegrations: v.optional(v.boolean()),
      marketing: v.optional(v.boolean()),
    }),
    deviceInfo: v.optional(v.object({
      platform: v.string(),
      osVersion: v.optional(v.string()),
      appVersion: v.optional(v.string()),
    })),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // Get current active consent
    const activeConsent = await ctx.db
      .query("userConsent")
      .withIndex("by_user_active", (q) =>
        q.eq("userId", args.userId).eq("isActive", true)
      )
      .first();

    if (!activeConsent) {
      throw new Error("No active consent found for user");
    }

    // Merge updates with existing consent
    const newSnapshot: ConsentSnapshot = {
      ...activeConsent.consentSnapshot,
      ...Object.fromEntries(
        Object.entries(args.updates).filter(([_, v]) => v !== undefined)
      ),
    } as ConsentSnapshot;

    // Deactivate current consent
    await ctx.db.patch(activeConsent._id, {
      isActive: false,
      updatedAt: now,
    });

    // Create new consent record
    const snapshotId = generateSnapshotId();
    const id = await ctx.db.insert("userConsent", {
      snapshotId,
      userId: args.userId,
      consentSnapshot: newSnapshot,
      deviceInfo: args.deviceInfo,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    });

    return { id, snapshotId };
  },
});

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Generate a unique snapshot ID
 */
function generateSnapshotId(): string {
  // Generate a UUID v4-like ID
  const timestamp = Date.now().toString(36);
  const randomPart = Math.random().toString(36).substring(2, 15);
  return `cs_${timestamp}_${randomPart}`;
}

/**
 * Validate consent snapshot has minimum required consents
 */
export function validateMinimumConsent(snapshot: ConsentSnapshot): {
  valid: boolean;
  missing: string[];
} {
  const required = ["dataProcessing"];
  const missing = required.filter(
    (key) => !snapshot[key as keyof ConsentSnapshot]
  );

  return {
    valid: missing.length === 0,
    missing,
  };
}

/**
 * Check if consent allows a specific feature
 */
export function canUseFeature(
  snapshot: ConsentSnapshot,
  feature: string
): boolean {
  switch (feature) {
    case "ai":
    case "suggestions":
    case "enrichment":
      return snapshot.aiFeatures && snapshot.dataProcessing;

    case "voice":
    case "transcription":
      return snapshot.voiceTranscription && snapshot.aiFeatures && snapshot.dataProcessing;

    case "calendar":
    case "integrations":
      return snapshot.thirdPartyIntegrations && snapshot.dataProcessing;

    case "sync":
    case "cloud":
      return snapshot.cloudSync && snapshot.dataProcessing;

    case "analytics":
    case "tracking":
      return snapshot.analytics;

    default:
      return snapshot.dataProcessing;
  }
}
