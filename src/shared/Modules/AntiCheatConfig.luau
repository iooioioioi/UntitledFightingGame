local Config = {}

-- ──────────────────────────────────────────────
-- WEBHOOK
-- ──────────────────────────────────────────────
Config.WEBHOOK_ENABLED = true
Config.WEBHOOK_URL     = "https://hooks.hyra.io/api/webhooks/1338651530621878413/oVtx0yaEyIfQExb1iqhYpUBnzzgerG_SIWn_zJOsccdteTc7BLTYXF_l_mw-R3ARX6xm"

-- ──────────────────────────────────────────────
-- BAN SYSTEM
-- ──────────────────────────────────────────────
Config.DATASTORE_NAME       = "AntiCheatV1"  -- separate from game data, easy to swap
Config.WARNINGS_BEFORE_BAN  = 3

-- ──────────────────────────────────────────────
-- FLAG THRESHOLDS
-- ──────────────────────────────────────────────
Config.MINOR_FLAGS_PER_WARNING = 4     -- minor flags within window = 1 warning
Config.MINOR_FLAG_WINDOW       = 60    -- seconds window for minor flag accumulation

-- ──────────────────────────────────────────────
-- SPEED DETECTION
-- ──────────────────────────────────────────────
Config.MAX_LEGITIMATE_SPEED    = 180   -- studs/s — above forward dash peak with buffer
Config.SPEED_SUSTAINED_TIME    = 0.6   -- seconds over max speed before flagging
Config.SPEED_POLL_INTERVAL     = 0.5   -- how often server checks velocity

-- ──────────────────────────────────────────────
-- POSITION DELTA DETECTION
-- ──────────────────────────────────────────────
Config.MAX_POSITION_DELTA      = 120   -- studs per poll interval before teleport flag
-- 180 studs/s * 0.5s poll = 90 max legitimate, 120 gives generous lag buffer

-- ──────────────────────────────────────────────
-- BLOCK TOGGLE DETECTION
-- ──────────────────────────────────────────────
Config.MIN_BLOCK_TOGGLE_INTERVAL  = 0.15   -- seconds minimum between block toggles
Config.RAPID_TOGGLE_COUNT         = 5      -- rapid toggles within window = minor flag
Config.RAPID_TOGGLE_WINDOW        = 3      -- seconds window for rapid toggle detection
Config.AUTO_BLOCK_VARIANCE        = 0.01   -- seconds — toggles within this variance = inhuman
Config.AUTO_BLOCK_SAMPLE          = 10     -- consecutive toggles to sample for variance

-- ──────────────────────────────────────────────
-- M1 TIMING DETECTION
-- ──────────────────────────────────────────────
Config.AUTO_CLICKER_VARIANCE      = 0.005  -- seconds — M1s within this variance = inhuman
Config.AUTO_CLICKER_SAMPLE        = 6      -- consecutive M1s to sample

-- ──────────────────────────────────────────────
-- REMOTE SPAM DETECTION
-- ──────────────────────────────────────────────
Config.REMOTE_SPAM_WINDOW         = 2      -- seconds window
Config.M1_MAX_RATE                = 4      -- max M1Hit fires per window (generous for lag)
Config.BLOCK_MAX_RATE             = 8      -- max BlockState fires per window

-- ──────────────────────────────────────────────
-- INFINITE BLOCK DETECTION
-- ──────────────────────────────────────────────
Config.MAX_BLOCK_HOLD_TIME        = 30     -- seconds before force-releasing block

-- ──────────────────────────────────────────────
-- WEBHOOK RATE LIMIT
-- ──────────────────────────────────────────────
Config.WEBHOOK_DEDUP_WINDOW       = 5      -- seconds before same message can repost

return Config