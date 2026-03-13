require "sqlite3"

class Cache
  def initialize(path, partition)
    @partition = partition
    @db = SQLite3::Database.new(path)

    @db.execute %{
      CREATE TABLE IF NOT EXISTS cache (
        partition TEXT,
        key TEXT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        content BLOB
      )
    }

    migrate_partition_schema!

    @db.execute %{
      CREATE INDEX IF NOT EXISTS cache_partition_key_timestamp
      ON cache(partition, key, timestamp)
    }
  end

  def fetch(key)
    row = @db.get_first_row(
      "SELECT content FROM cache WHERE partition = ? AND key = ? ORDER BY timestamp DESC LIMIT 1",
      [@partition, key]
    )

    return row[0] if row

    raise "no block given" unless block_given?

    content = yield

    @db.execute(
      "INSERT INTO cache (partition, key, content) VALUES (?, ?, ?)",
      [@partition, key, content]
    )

    content
  end

  def delete(key)
    @db.execute(
      "DELETE FROM cache WHERE partition = ? AND key = ?",
      [@partition, key]
    )
  end

  private

  def migrate_partition_schema!
    columns = @db.execute("PRAGMA table_info(cache)")
    return if columns.any? { |column| column[1] == "partition" }

    @db.execute("ALTER TABLE cache ADD COLUMN partition TEXT")
    @db.execute("UPDATE cache SET partition = ? WHERE partition IS NULL", "legacy")
  end
end
