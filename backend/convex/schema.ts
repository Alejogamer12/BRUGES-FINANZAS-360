import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  userProfiles: defineTable({
    subject: v.string(),
    role: v.union(v.literal("member"), v.literal("admin"), v.literal("owner")),
    status: v.union(v.literal("pending"), v.literal("active"), v.literal("blocked")),
    expiresAt: v.optional(v.number()),
    updatedAt: v.optional(v.number()),
  }).index("by_subject", ["subject"]),
  movements: defineTable({
    ownerId: v.id("userProfiles"),
    clientId: v.string(),
    kind: v.union(v.literal("income"), v.literal("expense")),
    amountMinor: v.number(),
    currency: v.string(),
    category: v.string(),
    note: v.string(),
    createdAt: v.number(),
    reviewState: v.literal("review"),
    source: v.literal("manual"),
  })
    .index("by_owner_created", ["ownerId", "createdAt"])
    .index("by_owner_client", ["ownerId", "clientId"]),
  accessRequests: defineTable({
    subject: v.string(),
    email: v.string(),
    status: v.union(v.literal("pending"), v.literal("approved"), v.literal("rejected")),
    requestedAt: v.number(),
  }).index("by_subject", ["subject"]),
  auditLogs: defineTable({
    actorId: v.id("userProfiles"),
    targetId: v.id("userProfiles"),
    action: v.string(),
    createdAt: v.number(),
    detail: v.string(),
  }).index("by_target_created", ["targetId", "createdAt"]),
});
