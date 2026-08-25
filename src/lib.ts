import { createClient } from '@supabase/supabase-js';
export const supabase = createClient(import.meta.env.VITE_SUPABASE_URL || '', import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || '');
export const slugify=(s:string)=>s.toLowerCase().trim().replace(/[^a-z0-9\u0600-\u06ff]+/g,'-').replace(/(^-|-$)/g,'');
