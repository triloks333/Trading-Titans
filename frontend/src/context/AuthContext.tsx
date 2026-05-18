import React, { createContext, useContext, useEffect, useState, PropsWithChildren, useCallback } from "react";
import { api, User, setToken, getToken } from "@/src/api/client";

interface AuthValue {
  user: User | null;
  initializing: boolean;
  refreshUser: () => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  register: (email: string, password: string, name: string) => Promise<void>;
  logout: () => Promise<void>;
}

const Ctx = createContext<AuthValue | undefined>(undefined);

export function AuthProvider({ children }: PropsWithChildren) {
  const [user, setUser] = useState<User | null>(null);
  const [initializing, setInitializing] = useState(true);

  const refreshUser = useCallback(async () => {
    try {
      const u = await api.me();
      setUser(u);
    } catch {
      setUser(null);
      await setToken(null);
    }
  }, []);

  useEffect(() => {
    (async () => {
      const t = await getToken();
      if (t) {
        await refreshUser();
      }
      setInitializing(false);
    })();
  }, [refreshUser]);

  const login: AuthValue["login"] = async (email, password) => {
    const res = await api.login(email, password);
    await setToken(res.access_token);
    setUser(res.user);
  };

  const register: AuthValue["register"] = async (email, password, name) => {
    const res = await api.register(email, password, name);
    await setToken(res.access_token);
    setUser(res.user);
  };

  const logout = async () => {
    await setToken(null);
    setUser(null);
  };

  return (
    <Ctx.Provider value={{ user, initializing, refreshUser, login, register, logout }}>
      {children}
    </Ctx.Provider>
  );
}

export function useAuth(): AuthValue {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAuth must be used within AuthProvider");
  return v;
}
