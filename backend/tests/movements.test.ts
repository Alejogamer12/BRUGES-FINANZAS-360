import { convexTest } from "convex-test";
import { describe, expect, it } from "vitest";
import schema from "../convex/schema";
import { anyApi } from "convex/server";

const api = anyApi;

const modules = import.meta.glob("../convex/**/*.ts");

describe("movement authorization and idempotence", () => {
  it("rejects unauthenticated access", async () => {
    const t = convexTest(schema, modules);
    await expect(t.query(api.movements.listOwn, {})).rejects.toThrow();
  });

  it("stores movements only for authenticated active profiles and deduplicates client ids", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity({ subject: "identity-alice", issuer: "test" });
    const bob = t.withIdentity({ subject: "identity-bob", issuer: "test" });

    await t.run(async (ctx) => {
      await ctx.db.insert("userProfiles", {
        subject: "identity-alice",
        role: "member",
        status: "active",
      });
      await ctx.db.insert("userProfiles", {
        subject: "identity-bob",
        role: "member",
        status: "active",
      });
    });

    const movement = {
      clientId: "android-local-1",
      kind: "expense" as const,
      amountMinor: 12345,
      currency: "COP",
      category: "Mercado",
      note: "Compra",
      createdAt: 1791489600000,
    };
    const first = await alice.mutation(api.movements.createManual, movement);
    const duplicate = await alice.mutation(api.movements.createManual, movement);
    const aliceRows = await alice.query(api.movements.listOwn, {});
    const bobRows = await bob.query(api.movements.listOwn, {});

    expect(first.created).toBe(true);
    expect(duplicate.created).toBe(false);
    expect(aliceRows).toHaveLength(1);
    expect(bobRows).toHaveLength(0);
  });

  it("rejects blocked and expired profiles", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("userProfiles", {
        subject: "identity-blocked",
        role: "member",
        status: "blocked",
      });
      await ctx.db.insert("userProfiles", {
        subject: "identity-expired",
        role: "member",
        status: "active",
        expiresAt: 1,
      });
    });

    const blocked = t.withIdentity({ subject: "identity-blocked", issuer: "test" });
    const expired = t.withIdentity({ subject: "identity-expired", issuer: "test" });
    await expect(blocked.query(api.movements.listOwn, {})).rejects.toThrow();
    await expect(expired.query(api.movements.listOwn, {})).rejects.toThrow();
  });

  it("allows only the server-designated owner to block a profile and records an audit event", async () => {
    const t = convexTest(schema, modules);
    const ids = await t.run(async (ctx) => {
      const ownerId = await ctx.db.insert("userProfiles", {
        subject: "identity-owner",
        role: "owner",
        status: "active",
      });
      const memberId = await ctx.db.insert("userProfiles", {
        subject: "identity-member",
        role: "member",
        status: "active",
      });
      return { ownerId, memberId };
    });
    const owner = t.withIdentity({ subject: "identity-owner", issuer: "test" });
    const member = t.withIdentity({ subject: "identity-member", issuer: "test" });

    await expect(
      member.mutation(api.admin.setUserAccess, {
        targetId: ids.memberId,
        status: "blocked",
      }),
    ).rejects.toThrow();
    await owner.mutation(api.admin.setUserAccess, {
      targetId: ids.memberId,
      status: "blocked",
    });
    await expect(member.query(api.movements.listOwn, {})).rejects.toThrow();

    const logs = await t.run((ctx) => ctx.db.query("auditLogs").collect());
    expect(logs).toHaveLength(1);
    expect(logs[0].action).toBe("set_user_access");
  });
});
