-- Force Reset All YouTube Channels
-- Run this in Supabase SQL Editor to clear all locks

UPDATE public.youtube_channels
SET 
  status = 'FREE',
  current_match_id = NULL,
  last_active_at = NOW();
