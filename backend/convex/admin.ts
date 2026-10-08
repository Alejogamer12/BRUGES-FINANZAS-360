import { mutation } from "./_generated/server";
import { ConvexError, v } from "convex/values";
import { requireOwner } from "./authz";

export const setUserAccess = mutation({
  args: {
    targetId: v.id("userProfiles"),
    status: v.union(v.literal("active"), v.literal("blocked"), v.literal("pending")),
    expiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const actor = await requireOwner(ctx);
    const target = await ctx.db.get(args.targetId);
    if (!target) throw new ConvexError("USER_NOT_FOUND");
    await ctx.db.patch(args.targetId, {
      status: args.status,
      expiresAt: args.expiresAt,
      updatedAt: Date.now(),
    });
    await ctx.db.insert("auditLogs", {
      actorId: actor._id,
      targetId: args.targetId,
      action: "set_user_access",
      createdAt: Date.now(),
      detail: `${target.status}->${args.status}`,
    });
    return { updated: true };
  },
});
