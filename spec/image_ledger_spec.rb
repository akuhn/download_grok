require "tmpdir"
require_relative "../image_ledger"

RSpec.describe ImageLedger do
  def with_ledger
    Dir.mktmpdir do |dir|
      ledger = ImageLedger.new(File.join(dir, "images.sqlite"))
      yield ledger
    end
  end

  it "inserts unique when fingerprint is new" do
    with_ledger do |ledger|
      result = ledger.record_download(
        username: "alice",
        conversation_id: "c1",
        source_url: "https://x.com/a",
        media_id: "100",
        path: "images/a.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      row = ledger.get_image(result.fetch(:media_id))
      expect(row.fetch("status")).to eq("unique")
      expect(row.fetch("canonical_media_id")).to be_nil
    end
  end

  it "marks second match as duplicate_delete and first as duplicate_keep" do
    with_ledger do |ledger|
      first = ledger.record_download(
        username: "alice",
        conversation_id: "c1",
        source_url: "https://x.com/a",
        media_id: "100",
        path: "images/a.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      second = ledger.record_download(
        username: "bob",
        conversation_id: "c2",
        source_url: "https://x.com/b",
        media_id: "101",
        path: "images/b.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      first_row = ledger.get_image(first.fetch(:media_id))
      second_row = ledger.get_image(second.fetch(:media_id))

      expect(first_row.fetch("status")).to eq("duplicate_keep")
      expect(second_row.fetch("status")).to eq("duplicate_delete")
      expect(second_row.fetch("canonical_media_id")).to eq(first_row.fetch("media_id"))
    end
  end

  it "keeps same canonical for repeated duplicates" do
    with_ledger do |ledger|
      first = ledger.record_download(
        username: "alice",
        conversation_id: "c1",
        source_url: "https://x.com/a",
        media_id: "100",
        path: "images/a.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      ledger.record_download(
        username: "bob",
        conversation_id: "c2",
        source_url: "https://x.com/b",
        media_id: "101",
        path: "images/b.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      third = ledger.record_download(
        username: "carol",
        conversation_id: "c3",
        source_url: "https://x.com/c",
        media_id: "102",
        path: "images/c.jpg",
        size_bytes: 1234,
        md5: "abc123",
      )

      first_row = ledger.get_image(first.fetch(:media_id))
      third_row = ledger.get_image(third.fetch(:media_id))

      expect(first_row.fetch("status")).to eq("duplicate_keep")
      expect(third_row.fetch("status")).to eq("duplicate_delete")
      expect(third_row.fetch("canonical_media_id")).to eq(first_row.fetch("media_id"))
    end
  end

  it "persists metadata fields" do
    with_ledger do |ledger|
      result = ledger.record_download(
        username: "dana",
        conversation_id: 44,
        source_url: "https://x.com/asset",
        media_id: 555,
        path: "images/d.jpg",
        size_bytes: 9876,
        md5: "ffff1111",
      )

      row = ledger.get_image(result.fetch(:media_id))
      expect(row.fetch("username")).to eq("dana")
      expect(row.fetch("conversation_id")).to eq("44")
      expect(row.fetch("media_id")).to eq("555")
      expect(row.fetch("path")).to eq("images/d.jpg")
      expect(row.fetch("size_bytes")).to eq(9876)
      expect(row.fetch("md5")).to eq("ffff1111")
      expect(row.keys).not_to include("id", "source_url", "downloaded_at", "updated_at")
    end
  end

  it "reports whether a source_url has already been indexed" do
    with_ledger do |ledger|
      source_url = "https://x.com/555"
      expect(ledger.include_source_url?(source_url)).to eq(false)

      ledger.record_download(
        username: "dana",
        conversation_id: "conv-44",
        source_url: source_url,
        media_id: "555",
        path: "images/d.jpg",
        size_bytes: 9876,
        md5: "ffff1111",
      )

      expect(ledger.include_source_url?(source_url)).to eq(true)
    end
  end

  it "updates stored path when a file moves folders" do
    with_ledger do |ledger|
      old_path = "images/conv_100.jpg"
      new_path = "project/conv_100.jpg"
      row = ledger.record_download(
        username: "dana",
        conversation_id: "conv",
        source_url: "https://x.com/asset",
        media_id: "100",
        path: old_path,
        size_bytes: 9876,
        md5: "ffff1111",
      )

      expect(ledger.rename_path(old_path, new_path)).to eq(1)
      expect(ledger.get_image(row.fetch(:media_id)).fetch("path")).to eq(new_path)
    end
  end

end
