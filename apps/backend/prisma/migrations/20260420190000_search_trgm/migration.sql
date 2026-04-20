-- pg_trgm extension fuer fuzzy search + ranked similarity
-- Extension wird schon via schema.prisma datasource.extensions angelegt, aber sicherheitshalber:
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN-Indexes fuer fuzzy-search auf Track.title, Artist.name, Album.title
CREATE INDEX IF NOT EXISTS track_title_trgm_idx ON "Track" USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS artist_name_trgm_idx ON "Artist" USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS album_title_trgm_idx ON "Album" USING gin (title gin_trgm_ops);
