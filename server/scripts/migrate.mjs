import "dotenv/config";
import { readFile } from "node:fs/promises";
import { Pool } from "pg";

const databaseURL = process.env.DATABASE_URL?.trim();
if (!databaseURL) throw new Error("DATABASE_URL is required");

const pool = new Pool({ connectionString: databaseURL });

try {
  for (const name of ["001_usage_limits.sql", "002_subscriptions.sql", "003_subscription_transactions.sql"]) {
    const migrationURL = new URL(`../migrations/${name}`, import.meta.url);
    const sql = await readFile(migrationURL, "utf8");
    await pool.query(sql);
    console.log(`Applied migration: ${name}`);
  }
} finally {
  await pool.end();
}
