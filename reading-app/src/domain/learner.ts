/**
 * Learner-state + activity contract shared by engine, storage and UI.
 * All times are epoch milliseconds supplied by callers (engine is pure: no Date.now(), no Math.random()).
 */

/** Practice tracks for each grapheme unit. */
export type Track = 'recognise' | 'blend' | 'segment' | 'read';
export const TRACKS: Track[] = ['recognise', 'blend', 'segment', 'read'];

export type ActivityType =
  | 'listen-choose-sound' | 'match-sound-grapheme' | 'find-grapheme' | 'blend-to-word' | 'order-sounds'
  | 'segment-word' | 'build-word' | 'read-pick-picture' | 'identify-tricky' | 'complete-sentence'
  | 'read-story' | 'fluency' | 'mixed-review';

export type SupportLevel = 'independent' | 'prompted' | 'modelled';

export interface Attempt {
  at: number;
  sessionId: string;
  unitId: string;
  track: Track;
  activityType: ActivityType;
  itemKey: string; // e.g. target grapheme or word
  correct: boolean;
  support: SupportLevel;
  responseMs: number | null;
  chosen?: string; // wrong answer chosen (for misconception tracking)
  expected?: string;
}

/** Per unit+track mastery evidence, derived from attempts but persisted for speed. */
export interface SkillState {
  unitId: string;
  track: Track;
  /** 0..1 smoothed independent accuracy (exponential moving average, recent attempts weigh more). */
  score: number;
  attempts: number;
  independentCorrect: number;
  sessionsSeen: string[]; // distinct session ids (capped)
  daysSeen: string[]; // distinct YYYY-MM-DD (capped)
  activityTypesSeen: ActivityType[];
  lastAttemptAt: number | null;
  recentResults: boolean[]; // last 8 independent results (true = correct)
  status: 'new' | 'learning' | 'secure' | 'review-due';
  /** Set when status first became secure. */
  secureAt: number | null;
  /** Index into review interval ladder; resets down after errors. */
  reviewStage: number;
  nextReviewAt: number | null;
  /** Count of consecutive struggle signals (drives intervention). */
  struggleStreak: number;
}

export interface ConfusionRecord { expected: string; chosen: string; count: number; lastAt: number }

export interface SessionSummary {
  id: string; startedAt: number; endedAt: number | null; activitiesDone: number; correct: number; independent: number;
  unitsPractised: string[]; stickersEarned: string[]; completed: boolean;
}

export interface MasterySettings {
  /** minimum smoothed score to be secure */ secureScore: number;
  /** minimum independent attempts */ minAttempts: number;
  /** minimum distinct sessions */ minSessions: number;
  /** minimum distinct days */ minDays: number;
  /** minimum distinct activity types */ minActivityTypes: number;
  /** last-N independent window must have at most this many errors */ maxRecentErrors: number;
  /** review ladder in days */ reviewLadderDays: number[];
  /** target session length in minutes */ sessionMinutes: number;
  /** speed used only as a mild tie-breaker; never penalises */ useResponseTime: boolean;
}

export const DEFAULT_MASTERY_SETTINGS: MasterySettings = {
  secureScore: 0.85, minAttempts: 6, minSessions: 2, minDays: 2, minActivityTypes: 2, maxRecentErrors: 1,
  reviewLadderDays: [1, 3, 7, 14, 30, 60], sessionMinutes: 7, useResponseTime: true,
};

export interface ParentOverride { unitId: string; mode: 'unlocked' | 'revisit'; at: number }

export interface LearnerSettings {
  muted: boolean; reducedMotion: boolean; narration: boolean; highContrast: boolean; largeText: boolean;
  mastery: MasterySettings;
}

export interface LearnerProfile {
  id: 'learner'; displayName: string; // nickname only, never a full name
  createdAt: number; baselineDone: boolean; baselinePlacementOrder: number | null;
  settings: LearnerSettings; stickers: string[]; overrides: ParentOverride[];
  schemaVersion: number; contentVersion: string;
}

export interface LearnerSnapshot {
  profile: LearnerProfile; skills: SkillState[]; confusions: ConfusionRecord[]; sessions: SessionSummary[];
  attempts: Attempt[];
}

/** Why a unit is in its current state; shown to parents. */
export type UnitStatus = 'locked' | 'available' | 'in-progress' | 'review-due' | 'mastered';
export interface UnitExplanation { unitId: string; status: UnitStatus; reason: string; blockedBy: string[] }

// ---------- Activities ----------
export interface Choice { id: string; label: string; audioId?: string; emoji?: string; correct: boolean }

export interface Activity {
  key: string; // stable id for this generated item
  type: ActivityType;
  unitId: string;
  track: Track;
  prompt: string; // short on-screen text
  spokenPrompt: string; // narration text (audioId lookup or caption)
  audioIds: string[]; // audio to play for the prompt (phoneme/word ids)
  /** type-specific payload; discriminated by `type` in the UI activity components */
  payload: ActivityPayload;
  /** every grapheme used must be taught by the learner's current knowledge; verified by tests */
  graphemesUsed: string[];
  trickyUsed: string[];
}

export type ActivityPayload =
  | { kind: 'choose'; choices: Choice[]; target: string; targetDisplay?: string; emoji?: string }
  | { kind: 'blend'; graphemes: string[]; word: string; choices?: Choice[]; emoji?: string }
  | { kind: 'order'; graphemes: string[]; tiles: string[]; word: string; emoji?: string }
  | { kind: 'segment'; word: string; graphemes: string[]; emoji?: string; tiles: string[] }
  | { kind: 'build'; word: string; graphemes: string[]; tiles: string[]; emoji?: string }
  | { kind: 'picture'; word: string; choices: Choice[] }
  | { kind: 'tricky'; word: string; choices: Choice[] }
  | { kind: 'sentence'; tokens: string[]; blankIndex: number; choices: Choice[]; emoji?: string }
  | { kind: 'story'; title: string; pages: { tokens: { text: string; tricky: boolean }[]; emoji?: string }[]; questions: { prompt: string; choices: Choice[] }[] }
  | { kind: 'fluency'; words: { text: string; graphemes: string[] }[]; softTargetSeconds: number };

export interface Answer { correct: boolean; support: SupportLevel; responseMs: number | null; chosen?: string; expected?: string }
