import { supabase, slugify } from './lib';
export const getSession=async()=>{const {data}=await supabase.auth.getSession();return data.session};
export const onAuthStateChange=(cb:any)=>supabase.auth.onAuthStateChange((_e,s)=>cb(s));
export const signUp=async(email:string,password:string,name:string)=>{const {error}=await supabase.auth.signUp({email,password,options:{data:{display_name:name}}});if(error)throw error};
export const signIn=async(email:string,password:string)=>{const {error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error};
export const signOut=async()=>{const {error}=await supabase.auth.signOut();if(error)throw error};
export const getProfile=async(uid:string)=>{const {data,error}=await supabase.from('profiles').select('*,roles(*)').eq('id',uid).single();if(error)throw error;return data};
export const getRoles=async()=>{const {data,error}=await supabase.from('roles').select('*').order('is_system',{ascending:false}).order('name');if(error)throw error;return data||[]};
export const getManga=async()=>{const {data,error}=await supabase.from('manga').select('*').order('created_at',{ascending:false});if(error)throw error;return data||[]};
export const getChapters=async()=>{const {data,error}=await supabase.from('chapters').select('*,chapter_pages(*),chapter_unlocks(*)').order('number');if(error)throw error;const rows:any[]=data||[];for(const c of rows){for(const p of (c.chapter_pages||[])){const {data:signed}=await supabase.storage.from('manga-pages').createSignedUrl(p.image_path,3600);p.image_url=signed?.signedUrl||'';}}return rows};
export const createManga=async(m:any)=>{const slug=slugify(m.title)+'-'+Date.now();const {data:{user}}=await supabase.auth.getUser();const {error}=await supabase.from('manga').insert({...m,slug,created_by:user?.id}).select().single();if(error)throw error};
export const createChapter=async(c:any)=>{const {data:{user}}=await supabase.auth.getUser();const {error}=await supabase.from('chapters').insert({...c,created_by:user?.id}).select().single();if(error)throw error};
export const uploadPages=async(chapterId:string,files:File[])=>{const sorted=files.filter(f=>f.type.startsWith('image/')).sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true}));for(let i=0;i<sorted.length;i++){const f=sorted[i],path=`${chapterId}/${String(i+1).padStart(4,'0')}-${f.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;const up=await supabase.storage.from('manga-pages').upload(path,f,{upsert:true,contentType:f.type});if(up.error)throw up.error;const {error}=await supabase.from('chapter_pages').upsert({chapter_id:chapterId,page_number:i+1,image_path:path,image_url:null},{onConflict:'chapter_id,page_number'});if(error)throw error}}
export const deleteManga=async(id:string)=>{const {error}=await supabase.from('manga').delete().eq('id',id);if(error)throw error};
export const spendPoints=async(chapterId:string)=>{const {data,error}=await supabase.rpc('spend_points',{p_chapter:chapterId});if(error)throw error;return !!data};
export const updateRole=async(uid:string,roleId:string)=>{const {error}=await supabase.from('profiles').update({role_id:roleId}).eq('id',uid);if(error)throw error};
export const createRole=async(name:string,permissions:any)=>{const {error}=await supabase.from('roles').insert({name,permissions});if(error)throw error};
export const updateProfilePoints=async(uid:string,amount:number)=>{const {error}=await supabase.from('profiles').update({points_balance:amount}).eq('id',uid);if(error)throw error};

export const adjustPoints=async(uid:string,delta:number,note:string)=>{const {data,error}=await supabase.rpc('admin_adjust_points',{target_user:uid,delta,note});if(error)throw error;return data};
