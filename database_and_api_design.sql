-- ====================================================================
-- HKPrimary CompRadar (學界通) - Database Schema & API Design
-- ====================================================================

-- Enable UUID extension for unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- --------------------------------------------------------------------
-- 1. ENUMS & LOOKUPS
-- --------------------------------------------------------------------

CREATE TYPE category_enum AS ENUM (
    '中文科',
    '英文科',
    '數學科',
    'STEAM項目',
    '體育',
    '視藝',
    '音樂',
    '常識',
    '人文',
    '科學',
    '其他'
);

CREATE TYPE target_grade_enum AS ENUM (
    'P1', 'P2', 'P3', 'P4', 'P5', 'P6',
    'Lower Primary (P.1-3)',
    'Upper Primary (P.4-6)',
    'Whole Primary (P.1-6)'
);

CREATE TYPE entry_type_enum AS ENUM (
    'Individual (個人賽)',
    'School Nomination / Team (學校推薦/團體賽)',
    'Both (個人及團體)'
);

CREATE TYPE organizer_type_enum AS ENUM (
    'EDB (教育局)',
    'University (大專院校)',
    'Government Dept (政府部門)',
    'NGO / Non-Profit (非牟利機構)',
    'Media / Commercial (傳媒/商業機構)'
);

-- --------------------------------------------------------------------
-- 2. TABLES
-- --------------------------------------------------------------------

-- Users Table (Teachers, Parents, School Admins)
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) CHECK (role IN ('teacher', 'parent', 'admin')),
    school_name VARCHAR(255), -- Optional, for HK primary school teachers
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Competitions Table (The core entity, updated daily)
CREATE TABLE competitions (
    competition_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title_zh VARCHAR(500) NOT NULL, -- Traditional Chinese title (Primary for HK)
    title_en VARCHAR(500),         -- English title if applicable
    slug VARCHAR(600) UNIQUE NOT NULL,
    
    -- Classification
    category category_enum NOT NULL,
    organizer_name VARCHAR(255) NOT NULL,
    organizer_type organizer_type_enum NOT NULL,
    
    -- Eligibility & Format
    target_grades TEXT[] NOT NULL, -- e.g., ARRAY['P.4', 'P.5', 'P.6']
    entry_type entry_type_enum NOT NULL,
    max_participants_per_school INT, -- NULL if unlimited
    fee_amount DECIMAL(10, 2) DEFAULT 0.00, -- 0 for free
    fee_currency VARCHAR(10) DEFAULT 'HKD',
    
    -- Key Dates
    enrollment_start_date TIMESTAMP WITH TIME ZONE,
    enrollment_deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    event_start_date TIMESTAMP WITH TIME ZONE,
    event_end_date TIMESTAMP WITH TIME ZONE,
    results_announcement_date TIMESTAMP WITH TIME ZONE,
    
    -- AI-Generated & Structured Summaries
    ai_summary_zh TEXT, -- TL;DR summary in Traditional Chinese
    eligibility_details TEXT,
    awards_description TEXT, -- e.g., 'Trophies, OEA certificate, Book vouchers'
    
    -- External Links & References
    source_url VARCHAR(1000) NOT NULL, -- Official website or EDB circular link
    pdf_attachment_url VARCHAR(1000),  -- Direct link to downloadable rules/pamphlet
    
    -- Metadata
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- User Bookmarks / Saved Competitions
CREATE TABLE user_bookmarks (
    bookmark_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    competition_id UUID REFERENCES competitions(competition_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, competition_id)
);

-- User Notification Preferences (By Category)
CREATE TABLE user_category_subscriptions (
    subscription_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    category category_enum NOT NULL,
    UNIQUE(user_id, category)
);

-- --------------------------------------------------------------------
-- 3. INDEXES FOR PERFORMANCE
-- --------------------------------------------------------------------

CREATE INDEX idx_competitions_category ON competitions(category);
CREATE INDEX idx_competitions_deadline ON competitions(enrollment_deadline);
CREATE INDEX idx_competitions_active ON competitions(is_active);
-- Full-text search index for Traditional Chinese and English titles
CREATE INDEX idx_competitions_search_zh ON competitions USING gin (to_tsvector('simple', title_zh));

-- ====================================================================
-- REST API DESIGN SPECIFICATIONS
-- ====================================================================

/*
BASE URL: https://api.primcomp.hk/v1

------------------------------------------------------------------------
1. COMPETITIONS ENDPOINTS
------------------------------------------------------------------------

GET /competitions
  Query Parameters:
    - category (string, optional): Filter by category (e.g., 'STEAM項目')
    - grade (string, optional): Filter by grade (e.g., 'P.5')
    - organizer_type (string, optional): Filter by organizer type
    - status (string, optional): 'upcoming', 'closing_soon', 'all' (Default: 'upcoming')
    - search (string, optional): Keyword search in title/organizer
    - page (int): Page number for pagination
    - limit (int): Items per page (default 20)
  Response:
    {
      "total": 142,
      "page": 1,
      "limit": 20,
      "data": [
        {
          "competition_id": "c1a2b3c4-...",
          "title_zh": "全港小學STEM創科挑戰賽 2026",
          "category": "STEAM項目",
          "organizer_name": "香港中文大學工程學院",
          "enrollment_deadline": "2026-05-15T23:59:59Z",
          "days_left": 12,
          "fee_amount": 0.00,
          "target_grades": ["P.4", "P.5", "P.6"],
          "source_url": "https://..."
        }
      ]
    }

GET /competitions/{id}
  Description: Get full details, AI summary, and document links for a specific competition.

GET /competitions/daily-digest
  Description: Returns competitions added or updated within the last 24 hours.

------------------------------------------------------------------------
2. USER BOOKMARKS ENDPOINTS (Requires Auth)
------------------------------------------------------------------------

GET /user/bookmarks
  Description: List all saved competitions for the logged-in teacher/parent.

POST /user/bookmarks
  Body: { "competition_id": "c1a2b3c4-..." }
  Description: Save a competition to bookmarks.

DELETE /user/bookmarks/{competition_id}
  Description: Remove a competition from bookmarks.

------------------------------------------------------------------------
3. CALENDAR INTEGRATION
------------------------------------------------------------------------

GET /competitions/{id}/ics
  Description: Generates and downloads an .ics calendar file for deadline/event syncing with Apple/Google/Outlook Calendar.
*/
