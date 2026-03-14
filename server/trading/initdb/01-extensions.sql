-- 01-extensions.sql
-- Load the TimescaleDB extension before any other schema objects are created.
-- This script runs first due to the numeric filename prefix.

CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
