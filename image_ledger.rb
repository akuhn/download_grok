require %(sqlite3)
require %(digest)

class ImageLedger
  def initialize(path)
    @db = SQLite3::Database.new(path)
    @db.results_as_hash = true
    ensure_schema!
  end

  def record_download(username:, conversation_id:, source_url:, media_id:, path:, size_bytes:, md5:)
    @db.transaction
    canonical = find_canonical(md5, size_bytes)

    if canonical
      mark_as_duplicate_keep(canonical["id"]) unless canonical["status"] == "duplicate_keep"
      row_id = insert_row(
        username: username,
        conversation_id: conversation_id,
        source_url: source_url,
        media_id: media_id,
        path: path,
        size_bytes: size_bytes,
        md5: md5,
        status: "duplicate_delete",
        canonical_image_id: canonical["id"],
      )
      @db.commit
      { id: row_id, status: "duplicate_delete", canonical_image_id: canonical["id"] }
    else
      row_id = insert_row(
        username: username,
        conversation_id: conversation_id,
        source_url: source_url,
        media_id: media_id,
        path: path,
        size_bytes: size_bytes,
        md5: md5,
        status: "unique",
        canonical_image_id: nil,
      )
      @db.commit
      { id: row_id, status: "unique", canonical_image_id: nil }
    end
  rescue StandardError
    @db.rollback
    raise
  end

  def record_file_download(username:, conversation_id:, source_url:, media_id:, source_path:, path:)
    self.record_download(
      username: username,
      conversation_id: conversation_id,
      source_url: source_url,
      media_id: media_id,
      path: path,
      size_bytes: File.size(source_path),
      md5: Digest::MD5.file(source_path).hexdigest,
    )
  end

  def get_image(id)
    @db.get_first_row("SELECT * FROM images WHERE id = ?", [id])
  end

  def get_images_for_fingerprint(md5, size_bytes)
    @db.execute(
      "SELECT * FROM images WHERE md5 = ? AND size_bytes = ? ORDER BY id",
      [md5, size_bytes]
    )
  end

  def include_source_url?(source_url)
    return false unless source_url

    row = @db.get_first_row(
      "SELECT id FROM images WHERE source_url = ? LIMIT 1",
      [source_url]
    )
    !!row
  end

  private

  def ensure_schema!
    @db.execute %{
      CREATE TABLE IF NOT EXISTS images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        downloaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        conversation_id TEXT,
        source_url TEXT,
        media_id TEXT,
        path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        md5 TEXT NOT NULL,
        status TEXT NOT NULL,
        canonical_image_id INTEGER,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    }

    @db.execute %{
      CREATE INDEX IF NOT EXISTS images_md5_size_bytes
      ON images(md5, size_bytes)
    }

    @db.execute %{
      CREATE INDEX IF NOT EXISTS images_source_url
      ON images(source_url)
    }

    @db.execute %{
      CREATE INDEX IF NOT EXISTS images_username_downloaded_at
      ON images(username, downloaded_at)
    }
  end

  def find_canonical(md5, size_bytes)
    @db.get_first_row(
      %{
        SELECT id, status
        FROM images
        WHERE md5 = ? AND size_bytes = ?
          AND status IN ('unique', 'duplicate_keep')
        ORDER BY id
        LIMIT 1
      },
      [md5, size_bytes]
    )
  end

  def mark_as_duplicate_keep(id)
    @db.execute(
      "UPDATE images SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
      ["duplicate_keep", id]
    )
  end

  def insert_row(username:, conversation_id:, source_url:, media_id:, path:, size_bytes:, md5:, status:, canonical_image_id:)
    @db.execute(
      %{
        INSERT INTO images (
          username, conversation_id, source_url, media_id, path,
          size_bytes, md5, status, canonical_image_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      },
      [username, conversation_id, source_url, media_id, path, size_bytes, md5, status, canonical_image_id]
    )
    @db.last_insert_row_id
  end
end
