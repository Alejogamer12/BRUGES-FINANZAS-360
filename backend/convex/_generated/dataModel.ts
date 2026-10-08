import type { DataModelFromSchemaDefinition, DocumentByName, TableNamesInDataModel } from "convex/server";
import schema from "../schema";

export type DataModel = DataModelFromSchemaDefinition<typeof schema>;
export type Id<TableName extends TableNamesInDataModel<DataModel>> =
  DocumentByName<DataModel, TableName>["_id"];
