import { mutation, query } from "./_generated/server";
import { ConvexError, v } from "convex/values";
import { requireActiveProfile } from "./authz";

const supportedCurrencies = new Set([
  "COP", "USD", "EUR", "MXN", "GBP", "CAD", "BRL", "PEN", "CLP", "ARS",
]);

export const listOwn = query({
  args: {},
  handler: async (ctx) => {
    const profile = await requireActiveProfile(ctx);
    const rows = await ctx.db
      .query("movements")
      .withIndex("by_owner_created", (q) => q.eq("ownerId", profile._id))
      .order("desc")
      .collect();
    return rows.map(({ _id, clientId, kind, amountMinor, currency, category, note, createdAt, reviewState, source }) => ({
      id: _id, clientId, kind, amountMinor, currency, category, note, createdAt, reviewState, source,
    }));
  },
});

export const createManual = mutation({
  args: {
    clientId: v.string(),
    kind: v.union(v.literal("income"), v.literal("expense")),
    amountMinor: v.number(),
    currency: v.string(),
    category: v.string(),
    note: v.string(),
    createdAt: v.number(),
  },
  handler: async (ctx, args) => {
    const profile = await requireActiveProfile(ctx);
    if (!Number.isSafeInteger(args.amountMinor) || args.amountMinor <= 0) {
      throw new ConvexError("INVALID_AMOUNT");
    }
    if (!supportedCurrencies.has(args.currency)) {
      throw new ConvexError("INVALID_CURRENCY");
    }
    if (!args.clientId.trim() || !args.category.trim()) {
      throw new ConvexError("INVALID_MOVEMENT");
    }
    const existing = await ctx.db
      .query("movements")
      .withIndex("by_owner_created", (q) => q.eq("ownerId", profile._id))
      .filter((q) => q.eq(q.field("clientId"), args.clientId))
      .unique();
    if (existing) return { created: false, id: existing._id };
    const id = await ctx.db.insert("movements", {
      ...args,
      ownerId: profile._id,
      reviewState: "review",
      source: "manual",
    });
    return { created: true, id };
  },
});
