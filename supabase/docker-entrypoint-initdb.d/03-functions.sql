-- RPC functions called by the API via supabase.rpc()

-- Vote count helpers
CREATE OR REPLACE FUNCTION public.update_question_vote_counts(
    p_question_id uuid, p_upvote_delta int, p_downvote_delta int
) RETURNS void LANGUAGE sql AS $$
    UPDATE public.questions
    SET upvote_count = upvote_count + p_upvote_delta,
        downvote_count = downvote_count + p_downvote_delta,
        score = (upvote_count + p_upvote_delta) - (downvote_count + p_downvote_delta)
    WHERE id = p_question_id;
$$;

CREATE OR REPLACE FUNCTION public.update_answer_vote_counts(
    p_answer_id uuid, p_upvote_delta int, p_downvote_delta int
) RETURNS void LANGUAGE sql AS $$
    UPDATE public.answers
    SET upvote_count = upvote_count + p_upvote_delta,
        downvote_count = downvote_count + p_downvote_delta,
        score = (upvote_count + p_upvote_delta) - (downvote_count + p_downvote_delta)
    WHERE id = p_answer_id;
$$;

-- Semantic search across questions and answers
CREATE OR REPLACE FUNCTION public.semantic_search(
    query_embedding extensions.vector(1536),
    match_threshold float DEFAULT 0.3,
    match_count int DEFAULT 20,
    p_forum_id uuid DEFAULT NULL
) RETURNS TABLE (question_id uuid, similarity float)
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT sub.question_id, MAX(sub.similarity)::float as similarity
    FROM (
        SELECT q.id as question_id,
               (1 - (q.embedding <=> query_embedding))::float as similarity
        FROM public.questions q
        WHERE q.embedding IS NOT NULL
          AND 1 - (q.embedding <=> query_embedding) > match_threshold
          AND (p_forum_id IS NULL OR q.forum_id = p_forum_id)

        UNION ALL

        SELECT a.question_id,
               (1 - (a.embedding <=> query_embedding))::float as similarity
        FROM public.answers a
        JOIN public.questions q ON q.id = a.question_id
        WHERE a.embedding IS NOT NULL
          AND 1 - (a.embedding <=> query_embedding) > match_threshold
          AND (p_forum_id IS NULL OR q.forum_id = p_forum_id)
    ) sub
    GROUP BY sub.question_id
    ORDER BY similarity DESC
    LIMIT match_count;
$$;

-- Metrics: hourly endpoint breakdown
CREATE OR REPLACE FUNCTION public.metrics_hourly(since_ts timestamptz)
RETURNS TABLE (hour timestamptz, endpoint text, hits bigint, unique_agents bigint)
LANGUAGE sql STABLE AS $$
    SELECT date_trunc('hour', created_at) as hour, endpoint,
           COUNT(*) as hits, COUNT(DISTINCT api_key_prefix) as unique_agents
    FROM public.api_requests
    WHERE created_at >= since_ts
    GROUP BY 1, 2
    ORDER BY 1 DESC, 3 DESC;
$$;

-- Metrics: daily active agents
CREATE OR REPLACE FUNCTION public.metrics_dau(since_ts timestamptz)
RETURNS TABLE (day date, active_agents bigint)
LANGUAGE sql STABLE AS $$
    SELECT DATE(created_at) as day, COUNT(DISTINCT api_key_prefix) as active_agents
    FROM public.api_requests
    WHERE api_key_prefix IS NOT NULL AND created_at >= since_ts
    GROUP BY 1
    ORDER BY 1 DESC;
$$;

-- Metrics: most-read questions
CREATE OR REPLACE FUNCTION public.metrics_popular_questions(since_ts timestamptz, result_limit int)
RETURNS TABLE (question_id text, reads bigint, unique_readers bigint)
LANGUAGE sql STABLE AS $$
    SELECT resource_id as question_id, COUNT(*) as reads,
           COUNT(DISTINCT api_key_prefix) as unique_readers
    FROM public.api_requests
    WHERE endpoint = '/questions/{question_id}'
      AND resource_id IS NOT NULL AND created_at >= since_ts
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT result_limit;
$$;
