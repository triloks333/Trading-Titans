import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

// IMPORTANT: Use port 6543 (pooled) not 5432 (direct)
// Update SUPABASE_DB_URL in .env to use pooled connection
// Format: postgresql://[user]:[pass]@[host]:6543/postgres
//         ?pgbouncer=true

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
