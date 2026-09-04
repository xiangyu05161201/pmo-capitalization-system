// GitHub Pages 静态前端可公开 publishable / anon key；请不要填写 service_role 或 secret key。
// 第四版使用独立数据表与独立文件桶，避免与第三版数据互相影响。
window.PMO_SUPABASE_CONFIG = {
  url: 'https://wbmmqeleeoinfrydexnj.supabase.co',
  anonKey: 'sb_publishable_EL7cs5eGcMKDUsAHJ9D--A_vYXC3xqD',
  storageBucket: 'project-materials-v4',
  tables: {
    profiles: 'v4_profiles',
    projects: 'v4_projects',
    events: 'v4_events',
    materials: 'v4_materials',
    fte_entries: 'v4_fte_entries'
  }
};
