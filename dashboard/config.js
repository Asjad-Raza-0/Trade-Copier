// Gold Trade Copier — Central System Configuration
window.APP_CONFIG = {
  // Default Master VPS Relay Server URL
  DEFAULT_RELAY_URL: 'http://3.11.8.205:8765',
  
  // Default Relay API Authentication Key
  DEFAULT_RELAY_KEY: 'ahgcjhbckjhsafkhkfuablhfkakkscknalkn7jhg3gd',
  
  // Default Supabase Cloud Database Credentials
  DEFAULT_SUPABASE_URL: '',
  DEFAULT_SUPABASE_KEY: '',

  // Helper getters using LocalStorage fallback
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
  }
};
