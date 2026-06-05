import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.REACT_APP_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.REACT_APP_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
export const supabase = createClient(supabaseUrl, supabaseAnonKey);

const activeChannels = {};

export function subscribeToPortfolio(userId, callback) {
  const channelName = `portfolio-changes-${userId}`;
  if (activeChannels[channelName]) {
    activeChannels[channelName].unsubscribe();
  }

  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'holdings',
        filter: `user_id=eq.${userId}`
      },
      (payload) => callback(payload)
    )
    .subscribe();

  activeChannels[channelName] = channel;
  return () => {
    channel.unsubscribe();
    delete activeChannels[channelName];
  };
}

export function subscribeToTrades(userId, callback) {
  const channelName = `trades-changes-${userId}`;
  if (activeChannels[channelName]) {
    activeChannels[channelName].unsubscribe();
  }

  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'orders',
        filter: `user_id=eq.${userId}`
      },
      (payload) => callback(payload)
    )
    .subscribe();

  activeChannels[channelName] = channel;
  return () => {
    channel.unsubscribe();
    delete activeChannels[channelName];
  };
}

export function subscribeToWatchlist(userId, callback) {
  const channelName = `watchlist-changes-${userId}`;
  if (activeChannels[channelName]) {
    activeChannels[channelName].unsubscribe();
  }

  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'watchlist',
        filter: `user_id=eq.${userId}`
      },
      (payload) => callback(payload)
    )
    .subscribe();

  activeChannels[channelName] = channel;
  return () => {
    channel.unsubscribe();
    delete activeChannels[channelName];
  };
}

export function subscribeToCryptoPortfolio(userId, callback) {
  const channelName = `crypto-portfolio-changes-${userId}`;
  if (activeChannels[channelName]) {
    activeChannels[channelName].unsubscribe();
  }

  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'crypto_holdings',
        filter: `user_id=eq.${userId}`
      },
      (payload) => callback(payload)
    )
    .subscribe();

  activeChannels[channelName] = channel;
  return () => {
    channel.unsubscribe();
    delete activeChannels[channelName];
  };
}

export function subscribeToNotifications(userId, callback) {
  const channelName = `notifications-changes-${userId}`;
  if (activeChannels[channelName]) {
    activeChannels[channelName].unsubscribe();
  }

  const channel = supabase
    .channel(channelName)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'notifications',
        filter: `user_id=eq.${userId}`
      },
      (payload) => callback(payload)
    )
    .subscribe();

  activeChannels[channelName] = channel;
  return () => {
    channel.unsubscribe();
    delete activeChannels[channelName];
  };
}

export function unsubscribeAll() {
  Object.keys(activeChannels).forEach((key) => {
    activeChannels[key].unsubscribe();
    delete activeChannels[key];
  });
}
