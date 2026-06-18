-- Enable Row Level Security on staging tables to secure them from public/anonymous access
ALTER TABLE public.nse_fo_bhavcopy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nse_instrument_lots ENABLE ROW LEVEL SECURITY;
