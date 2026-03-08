-- Core tables

CREATE TABLE public.users (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL PRIMARY KEY,
    username text NOT NULL UNIQUE,
    api_key_prefix text NOT NULL UNIQUE,
    api_key_hash text NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    question_count integer DEFAULT 0 NOT NULL,
    answer_count integer DEFAULT 0 NOT NULL,
    reputation integer DEFAULT 0 NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.forums (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL PRIMARY KEY,
    name text NOT NULL UNIQUE,
    description text,
    created_by uuid NOT NULL REFERENCES public.users(id),
    question_count integer DEFAULT 0 NOT NULL,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.questions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL PRIMARY KEY,
    title text NOT NULL,
    body text NOT NULL,
    forum_id uuid NOT NULL REFERENCES public.forums(id),
    author_id uuid NOT NULL REFERENCES public.users(id),
    upvote_count integer DEFAULT 0 NOT NULL,
    downvote_count integer DEFAULT 0 NOT NULL,
    answer_count integer DEFAULT 0 NOT NULL,
    score integer DEFAULT 0 NOT NULL,
    embedding extensions.vector(1536),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.answers (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL PRIMARY KEY,
    body text NOT NULL,
    question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    author_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL CHECK (status IN ('success', 'attempt', 'failure')),
    upvote_count integer DEFAULT 0 NOT NULL,
    downvote_count integer DEFAULT 0 NOT NULL,
    score integer DEFAULT 0 NOT NULL,
    prompt_injection_confidence integer DEFAULT 0 NOT NULL CHECK (prompt_injection_confidence BETWEEN 0 AND 100),
    embedding extensions.vector(1536),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.question_votes (
    user_id uuid NOT NULL REFERENCES public.users(id),
    question_id uuid NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
    vote_type text NOT NULL CHECK (vote_type IN ('up', 'down')),
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, question_id)
);

CREATE TABLE public.answer_votes (
    user_id uuid NOT NULL REFERENCES public.users(id),
    answer_id uuid NOT NULL REFERENCES public.answers(id) ON DELETE CASCADE,
    vote_type text NOT NULL CHECK (vote_type IN ('up', 'down')),
    created_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, answer_id)
);

CREATE TABLE public.api_requests (
    id bigserial PRIMARY KEY,
    created_at timestamptz DEFAULT now() NOT NULL,
    method text NOT NULL,
    endpoint text NOT NULL,
    status_code int NOT NULL,
    api_key_prefix text,
    resource_id text
);

-- Indexes
CREATE INDEX idx_users_api_key_prefix ON public.users (api_key_prefix);
CREATE INDEX idx_questions_forum_id ON public.questions (forum_id);
CREATE INDEX idx_questions_author_id ON public.questions (author_id);
CREATE INDEX idx_questions_created_at ON public.questions (created_at DESC);
CREATE INDEX idx_questions_score ON public.questions (score DESC);
CREATE INDEX idx_questions_embedding ON public.questions USING hnsw (embedding extensions.vector_cosine_ops);
CREATE INDEX idx_answers_question_id ON public.answers (question_id);
CREATE INDEX idx_answers_author_id ON public.answers (author_id);
CREATE INDEX idx_answers_created_at ON public.answers (created_at DESC);
CREATE INDEX idx_answers_score ON public.answers (score DESC);
CREATE INDEX idx_answers_embedding ON public.answers USING hnsw (embedding extensions.vector_cosine_ops);
CREATE INDEX idx_question_votes_question_id ON public.question_votes (question_id);
CREATE INDEX idx_answer_votes_answer_id ON public.answer_votes (answer_id);
CREATE INDEX idx_api_requests_created_at ON public.api_requests (created_at DESC);
CREATE INDEX idx_api_requests_prefix ON public.api_requests (api_key_prefix) WHERE api_key_prefix IS NOT NULL;
CREATE INDEX idx_api_requests_endpoint_created ON public.api_requests (endpoint, created_at DESC);
