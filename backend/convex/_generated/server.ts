// Minimal local codegen-compatible wrappers. Replace with `npx convex codegen`
// after linking the production deployment.
import type { GenericMutationCtx, GenericQueryCtx } from "convex/server";
import { mutationGeneric, queryGeneric } from "convex/server";
import type { DataModel } from "./dataModel";

export type QueryCtx = GenericQueryCtx<DataModel>;
export type MutationCtx = GenericMutationCtx<DataModel>;
export const query = queryGeneric;
export const mutation = mutationGeneric;
