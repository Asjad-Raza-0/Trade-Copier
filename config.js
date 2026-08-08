// Gold Trade Copier — Central System Configuration
window.APP_CONFIG = {
  // Default Master VPS Relay Server URL (Use /api on HTTPS deployments to bypass Mixed Content blocks)
  DEFAULT_RELAY_URL: window.location.protocol === 'https:' ? '/api' : 'http://3.11.8.205:8765',
  
  // Target Master VPS IP (Proxied by Cloudflare Edge Function)
  DEFAULT_VPS_IP: 'http://3.11.8.205:8765',

  // Default Relay API Authentication Key
  DEFAULT_RELAY_KEY: 'ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd',
  
  // Default Supabase Cloud Database Credentials
  DEFAULT_SUPABASE_URL: '',
  DEFAULT_SUPABASE_KEY: '',

  // Default Admin Passcode for Live Dashboard Protection
  DEFAULT_ADMIN_PIN: '7890',

  // Helper getters using LocalStorage / SessionStorage
  getRelayUrl: function() {
    return localStorage.getItem('RELAY_URL') || this.DEFAULT_RELAY_URL;
  },
  getRelayKey: function() {
    return localStorage.getItem('RELAY_KEY') || this.DEFAULT_RELAY_KEY;
  },
  getSupabaseUrl: function() {
    return localStorage.getItem('SUPABASE_URL') || this.DEFAULT_SUPABASE_URL;
  },
  getSupabaseKey: function() {
    return localStorage.getItem('SUPABASE_KEY') || this.DEFAULT_SUPABASE_KEY;
  },
  getAdminPin: function() {
    return localStorage.getItem('ADMIN_PIN') || this.DEFAULT_ADMIN_PIN;
  },
  isAdminAuthenticated: function() {
    return sessionStorage.getItem('ADMIN_AUTH') === 'true';
  },
  setAdminAuthenticated: function(status) {
    sessionStorage.setItem('ADMIN_AUTH', status ? 'true' : 'false');
  }
};
