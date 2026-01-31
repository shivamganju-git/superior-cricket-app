-- YouTube Channel Pool Schema
-- Run this in Supabase SQL Editor

-- 1. Create Status Enum
DO $$ BEGIN
    CREATE TYPE youtube_channel_status AS ENUM ('FREE', 'IN_USE');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. YouTube Channels table
CREATE TABLE IF NOT EXISTS public.youtube_channels (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  channel_id TEXT NOT NULL UNIQUE,
  channel_name TEXT,
  refresh_token TEXT NOT NULL,
  status youtube_channel_status DEFAULT 'FREE',
  current_match_id UUID, -- Removed FK constraint to allow temporary match IDs
  last_active_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  stream_key TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Match Videos table (Archive)
CREATE TABLE IF NOT EXISTS public.match_videos (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE NOT NULL,
  video_id TEXT NOT NULL UNIQUE,
  replay_url TEXT,
  status TEXT DEFAULT 'archived',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Enable RLS
ALTER TABLE public.youtube_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_videos ENABLE ROW LEVEL SECURITY;

-- 5. Policies
DROP POLICY IF EXISTS "Public can view active channel status" ON public.youtube_channels;
CREATE POLICY "Public can view active channel status" ON public.youtube_channels
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admins can manage channels" ON public.youtube_channels;
CREATE POLICY "Admins can manage channels" ON public.youtube_channels
  FOR ALL USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "Public can view match videos" ON public.match_videos;
CREATE POLICY "Public can view match videos" ON public.match_videos
  FOR SELECT USING (true);

-- 6. RPC: Get Free Channel (Transaction Safe)
CREATE OR REPLACE FUNCTION public.get_free_youtube_channel(p_match_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_channel_id UUID;
  v_result RECORD;
BEGIN
  -- Find the first free channel and lock the row
  SELECT id INTO v_channel_id
  FROM public.youtube_channels
  WHERE status = 'FREE'
  ORDER BY last_active_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_channel_id IS NULL THEN
    RETURN jsonb_build_object('error', 'No free channels available');
  END IF;

  -- Assign the channel
  UPDATE public.youtube_channels
  SET 
    status = 'IN_USE',
    current_match_id = p_match_id,
    last_active_at = NOW()
  WHERE id = v_channel_id
  RETURNING * INTO v_result;

  RETURN jsonb_build_object(
    'id', v_result.id,
    'channel_id', v_result.channel_id,
    'refresh_token', v_result.refresh_token,
    'stream_key', v_result.stream_key
  );
END;
$$;

-- 7. RPC: Release Channel
CREATE OR REPLACE FUNCTION public.release_youtube_channel(p_match_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.youtube_channels
  SET 
    status = 'FREE',
    current_match_id = NULL,
    last_active_at = NOW()
  WHERE current_match_id = p_match_id;
END;
$$;

-- 8. RPC: Get Assigned Channel Credentials (for ending a match)
CREATE OR REPLACE FUNCTION public.get_assigned_youtube_channel(p_match_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result RECORD;
BEGIN
  SELECT * INTO v_result
  FROM public.youtube_channels
  WHERE current_match_id = p_match_id
  LIMIT 1;

  IF v_result.id IS NULL THEN
    RETURN jsonb_build_object('error', 'No channel assigned to this match');
  END IF;

  RETURN jsonb_build_object(
    'id', v_result.id,
    'channel_id', v_result.channel_id,
    'refresh_token', v_result.refresh_token,
    'stream_key', v_result.stream_key
  );
END;
$$;
