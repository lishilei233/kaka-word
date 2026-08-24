import "dotenv/config";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";
const databaseURL = process.env.DATABASE_URL?.trim();
if (!databaseURL)
    throw new Error("DATABASE_URL is required");
const migrationURL = new URL("../../migrations/001_usage_limits.sql", import.meta.url);
const sql = await readFile(migrationURL, "utf8");
const pool = new Pool({ connectionString: databaseURL });
try {
    await pool.query(sql);
    console.log("Applied migration: 001_usage_limits.sql");
}
finally {
    await pool.end();
}
