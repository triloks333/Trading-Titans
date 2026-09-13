/// Backend configuration.
///
/// The vault deliberately shares the Trading Titans Supabase project (same
/// auth users, same Postgres, same storage service). Every vault object lives
/// behind a `kv_` table prefix / `kv-*` bucket prefix so the two products can
/// never collide.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://bftvimnhpoiuoyryyiff.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak',
);

/// Storage buckets (private; every read goes through a short-lived signed URL).
const String bucketDocuments = 'kv-documents';
const String bucketSignatures = 'kv-signatures';
const String bucketImages = 'kv-images';

/// Signed-URL lifetime for previews/downloads and for "share link" actions.
const int signedUrlSeconds = 60 * 60;

const List<String> documentCategories = [
  'Registration',
  'GST',
  'PAN',
  'Bank Documents',
  'Agreements',
  'Legal',
  'Tax',
  'Finance',
  'HR',
  'Other',
];

const List<String> personalCategories = [
  'Aadhaar',
  'PAN',
  'Passport',
  'Driving License',
  'Resume',
  'Certificates',
  'Insurance',
  'Personal Contracts',
  'Other',
];

/// Where the content came from.
const List<String> linkCategories = [
  'Instagram Reel',
  'Instagram Post',
  'YouTube Short',
  'YouTube Video',
  'LinkedIn Post',
  'Twitter/X Post',
  'Facebook Post',
  'WhatsApp Forward',
  'Podcast',
  'Newsletter',
  'Website',
  'Article',
  'Research Report',
  'Tool / App',
  'Other',
];

/// Why the content was saved. Kept separate from the platform so the same reel
/// can be found as "Business idea" months later.
const List<String> linkThemes = [
  'Business idea',
  'Marketing',
  'Branding',
  'Sales',
  'Product',
  'Technology',
  'Finance',
  'Legal & compliance',
  'Hiring & team',
  'Competitor watch',
  'Inspiration',
  'Learning',
  'Fun',
  'Other',
];

const List<String> noteCategories = [
  'General',
  'Meeting',
  'Idea',
  'Decision',
  'Process',
  'Finance',
  'Client',
  'Reminder',
  'Other',
];

const List<String> todoPriorities = ['Low', 'Normal', 'High', 'Urgent'];

const List<String> imageAlbums = [
  'General',
  'Posters',
  'Logos',
  'Screenshots',
  'Branding Assets',
  'Mockups',
];

const List<String> memberRoles = ['owner', 'admin', 'member', 'viewer'];
