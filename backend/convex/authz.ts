import { ConvexError } from "convex/values";
import type { MutationCtx, QueryCtx } from "./_generated/server";

export async function requireActiveProfile(ctx: QueryCtx | MutationCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError("UNAUTHENTICATED");
  const profile = await ctx.db
    .query("userProfiles")
    .withIndex("by_subject", (q) => q.eq("subject", identity.subject))
    .unique();
  if (!profile || profile.status !== "active") {
    throw new ConvexError("ACCESS_DENIED");
  }
  if (profile.expiresAt !== undefined && profile.expiresAt <= Date.now()) {
    throw new ConvexError("ACCESS_EXPIRED");
  }
  return profile;
}

export async function requireOwner(ctx: MutationCtx) {
  const profile = await requireActiveProfile(ctx);
  if (profile.role !== "owner") throw new ConvexError("OWNER_REQUIRED");
  return profile;
}
