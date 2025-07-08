

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "ServicePlus";


ALTER SCHEMA "ServicePlus" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."dent_damage_webhook"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Only proceed if the inserted row is damaged
    IF NEW.is_damaged = 'true' THEN
        -- Update the ticket_status in the Master table
        UPDATE "Master"
        SET ticket_status = 'Hot Lead'
        WHERE id = NEW.lead_id
          AND ticket_status = 'Target Lead';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."dent_damage_webhook"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_advisor_summary"("advisor_name_input" "text", "branch_input" "text", "start_date_input" "text", "end_date_input" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Convert 'Null' strings to real NULL
    start_date := NULLIF(start_date_input, 'Null')::DATE;
    end_date := NULLIF(end_date_input, 'Null')::DATE;

    SELECT json_build_object(
        'advisor_name', advisor_name_input,
        'branch', branch_input,
        'total_leads', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
        'hot_leads', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status = 'Hot Lead'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
        'conversions', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status = 'Conversion'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
        'incentive_count', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
        'incentive_count_InDealer', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND lead_type = 'In-Dealer'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
        'incentive_count_External', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND lead_type = 'External'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
         'incentive_count_External_Minor_Damage', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND lead_type = 'External'
            AND "Car_Damage" = 'Minor Damage'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
         'incentive_count_External_Medium_Damage', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND lead_type = 'External'
            AND "Car_Damage" = 'Medium Damage'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0),
         'incentive_count_External_Major_Damage', COALESCE(COUNT(*) FILTER (
            WHERE advisor_name = advisor_name_input
            AND branch = branch_input
            AND ticket_status IS DISTINCT FROM 'Cold Lead'
            AND ticket_status IS DISTINCT FROM 'Target Lead'
            AND lead_type = 'External'
            AND "Car_Damage" = 'Major Damage'
            AND (start_date IS NULL OR created_at::date >= start_date)
            AND (end_date IS NULL OR created_at::date <= end_date)
        ), 0)
    ) INTO result
    FROM "Master";

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_advisor_summary"("advisor_name_input" "text", "branch_input" "text", "start_date_input" "text", "end_date_input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_branch_advisors_summary"("branch_input" "text", "start_date_input" "text", "end_date_input" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    start_date DATE;
    end_date DATE;
BEGIN
    -- Convert string 'Null' to actual NULLs
    start_date := NULLIF(start_date_input, 'Null')::DATE;
    end_date := NULLIF(end_date_input, 'Null')::DATE;

    SELECT json_agg(row_to_json(t)) INTO result
    FROM (
        SELECT 
            ROW_NUMBER() OVER (ORDER BY 
                COUNT(*) FILTER (
                    WHERE ticket_status = 'Hot Lead'
                    AND (start_date IS NULL OR created_at::date >= start_date)
                    AND (end_date IS NULL OR created_at::date <= end_date)
                ) DESC
            ) AS no,
            advisor_name,
            COUNT(*) FILTER (
                WHERE ticket_status = 'Hot Lead'
                AND (start_date IS NULL OR created_at::date >= start_date)
                AND (end_date IS NULL OR created_at::date <= end_date)
            ) AS hot_leads,
            COUNT(*) FILTER (
                WHERE ticket_status = 'Conversion'
                AND (start_date IS NULL OR created_at::date >= start_date)
                AND (end_date IS NULL OR created_at::date <= end_date)
            ) AS conversions,
            COUNT(*) FILTER (
                WHERE ticket_status IS DISTINCT FROM 'Cold Lead'
                AND (start_date IS NULL OR created_at::date >= start_date)
                AND (end_date IS NULL OR created_at::date <= end_date)
            ) AS incentive_count
        FROM "Master"
        WHERE branch = branch_input
        GROUP BY advisor_name
    ) t;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_branch_advisors_summary"("branch_input" "text", "start_date_input" "text", "end_date_input" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_filtered_master_data"("p_advisor_name" "text" DEFAULT NULL::"text", "p_pic" "text" DEFAULT NULL::"text", "p_branch" "text" DEFAULT NULL::"text", "p_ticket_status" "text" DEFAULT NULL::"text", "p_lead_type" "text" DEFAULT NULL::"text", "p_service_type" "text" DEFAULT NULL::"text", "p_auth_role" "text" DEFAULT NULL::"text", "p_auth_branch" "text" DEFAULT NULL::"text", "p_from_date" "text" DEFAULT NULL::"text", "p_to_date" "text" DEFAULT NULL::"text", "p_sort_order" "text" DEFAULT NULL::"text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    branch_filter TEXT;
    order_by_clause TEXT;
BEGIN
    -- Convert "null" string to actual NULL
    from_timestamp := NULLIF(p_from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(p_to_date, 'null')::TIMESTAMP;
    
    -- Set branch filter based on role
    branch_filter := CASE 
        WHEN p_auth_role = 'Admin' THEN p_auth_branch
        ELSE NULL
    END;
    
    -- Determine sorting order
    order_by_clause := CASE 
        WHEN p_sort_order = 'created - oldest to newest' THEN 'created_at ASC'
        WHEN p_sort_order = 'created - newest to oldest' THEN 'created_at DESC'
        WHEN p_sort_order = 'updated - oldest to newest' THEN 'update_time ASC'
        ELSE 'update_time DESC'
    END;
    
    -- Query the data with filtering conditions
    SELECT json_agg(t) INTO result
    FROM (
        SELECT * FROM "Master"
        WHERE (p_advisor_name IS NULL OR p_advisor_name = 'null' OR "advisor_name" = p_advisor_name)
        AND (p_pic IS NULL OR p_pic = 'null' OR "pic" = p_pic)
        AND (p_branch IS NULL OR p_branch = 'null' OR "branch" = COALESCE(branch_filter, p_branch))
        AND (p_ticket_status IS NULL OR p_ticket_status = 'null' OR "ticket_status" = p_ticket_status)
        AND (p_lead_type IS NULL OR p_lead_type = 'null' OR "lead_type" = p_lead_type)
        AND (p_service_type IS NULL OR p_service_type = 'null' OR "service_type" = p_service_type)
        AND (from_timestamp IS NULL OR "created_at" >= from_timestamp)
        AND (to_timestamp IS NULL OR "created_at" <= to_timestamp)
        ORDER BY order_by_clause
    ) t;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_filtered_master_data"("p_advisor_name" "text", "p_pic" "text", "p_branch" "text", "p_ticket_status" "text", "p_lead_type" "text", "p_service_type" "text", "p_auth_role" "text", "p_auth_branch" "text", "p_from_date" "text", "p_to_date" "text", "p_sort_order" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data"("advisor_name" "text" DEFAULT NULL::"text", "pic" "text" DEFAULT NULL::"text", "branch" "text" DEFAULT NULL::"text", "ticket_status" "text" DEFAULT NULL::"text", "lead_type" "text" DEFAULT NULL::"text", "service_type" "text" DEFAULT NULL::"text", "from_date" "text" DEFAULT NULL::"text", "to_date" "text" DEFAULT NULL::"text", "sort_order" "text" DEFAULT NULL::"text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column TEXT;
    order_by_direction TEXT;
BEGIN
    -- Convert input dates to timestamps, treating 'null' as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'DESC';
    END IF;

    -- Select and filter data dynamically
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            ORDER BY %I %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        order_by_column, order_by_direction
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data"("advisor_name" "text" DEFAULT NULL::"text", "pic" "text" DEFAULT NULL::"text", "branch" "text" DEFAULT NULL::"text", "ticket_status" "text" DEFAULT NULL::"text", "lead_type" "text" DEFAULT NULL::"text", "service_type" "text" DEFAULT NULL::"text", "from_date" "text" DEFAULT NULL::"text", "to_date" "text" DEFAULT NULL::"text", "sort_order" "text" DEFAULT NULL::"text", "limit_rows" integer DEFAULT 3, "offset_rows" integer DEFAULT 0) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column TEXT;
    order_by_direction TEXT;
BEGIN
    -- Convert input dates to timestamps, treating 'null' as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'DESC';
    END IF;

    -- Execute the query dynamically with pagination
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data"("advisor_name" "text" DEFAULT NULL::"text", "pic" "text" DEFAULT NULL::"text", "branch" "text" DEFAULT NULL::"text", "ticket_status" "text" DEFAULT NULL::"text", "lead_type" "text" DEFAULT NULL::"text", "service_type" "text" DEFAULT NULL::"text", "from_date" "text" DEFAULT NULL::"text", "to_date" "text" DEFAULT NULL::"text", "sort_order" "text" DEFAULT NULL::"text", "limit_rows" integer DEFAULT 3, "offset_rows" integer DEFAULT 0, "authrole" "text" DEFAULT 'User'::"text", "authbranch" "text" DEFAULT NULL::"text") RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column TEXT;
    order_by_direction TEXT;
    branch_filter TEXT;
BEGIN
    -- Convert input dates to timestamps, treating 'null' as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;  -- Use authbranch if the role is 'Admin'
    ELSE
        branch_filter := NULL;  -- Otherwise, NULL to not filter by branch
    END IF;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'DESC';
    END IF;

    -- Execute the query dynamically with pagination and role-based branch filter
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)  -- Role-based branch filter
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        branch_filter, branch_filter,  -- Branch filter based on role
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer, "authrole" "text", "authbranch" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data"("advisor_name" "text" DEFAULT NULL::"text", "pic" "text" DEFAULT NULL::"text", "branch" "text" DEFAULT NULL::"text", "authrole" "text" DEFAULT NULL::"text", "authbranch" "text" DEFAULT NULL::"text", "ticket_status" "text" DEFAULT NULL::"text", "lead_type" "text" DEFAULT NULL::"text", "service_type" "text" DEFAULT NULL::"text", "from_date" "text" DEFAULT NULL::"text", "to_date" "text" DEFAULT NULL::"text", "sort_order" "text" DEFAULT NULL::"text", "limit_rows" integer DEFAULT 3, "offset_rows" integer DEFAULT 0) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column TEXT;
    order_by_direction TEXT;
BEGIN
    -- Convert input dates to timestamps, treating 'null' as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'DESC';
    END IF;

    -- Execute the query dynamically with pagination
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)  -- Existing branch filter
            AND (%L = '' OR "branch" = %L)  -- New branch filter based on authrole and authbranch
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        branch, branch,  -- Existing branch filter
        authrole,        -- authrole condition
        authbranch,      -- authbranch condition
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "authrole" "text", "authbranch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data"("advisor_name" character varying DEFAULT NULL::character varying, "pic" character varying DEFAULT NULL::character varying, "branch" character varying DEFAULT NULL::character varying, "ticket_status" character varying DEFAULT NULL::character varying, "lead_type" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "sort_order" character varying DEFAULT NULL::character varying, "limit_rows" integer DEFAULT 3, "offset_rows" integer DEFAULT 0, "authrole" character varying DEFAULT 'User'::character varying, "authbranch" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column VARCHAR;
    order_by_direction VARCHAR;
    branch_filter VARCHAR;
BEGIN
    -- Convert input dates to timestamps, treating 'null' as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;
    ELSE
        branch_filter := NULL;
    END IF;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'DESC';
    END IF;

    -- Execute the query dynamically with pagination and role-based branch filter
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        branch_filter, branch_filter,  
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data1"("advisor_name" character varying DEFAULT NULL::character varying, "pic" character varying DEFAULT NULL::character varying, "branch" character varying DEFAULT NULL::character varying, "ticket_status" character varying DEFAULT NULL::character varying, "lead_type" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "sort_order" character varying DEFAULT NULL::character varying, "limit_rows" integer DEFAULT 3, "offset_rows" integer DEFAULT 0, "authrole" character varying DEFAULT 'User'::character varying, "authbranch" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    order_by_column VARCHAR;
    order_by_direction VARCHAR;
    branch_filter VARCHAR;
BEGIN
    -- Convert string 'Null' to actual NULL
    advisor_name := NULLIF(advisor_name, 'Null');
    pic := NULLIF(pic, 'Null');
    branch := NULLIF(branch, 'Null');
    ticket_status := NULLIF(ticket_status, 'Null');
    lead_type := NULLIF(lead_type, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    authbranch := NULLIF(authbranch, 'Null');

    -- Convert input dates to timestamps, treating NULL as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;
    ELSE
        branch_filter := NULL;
    END IF;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'udpate_time';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'updated -newest to oldest' THEN
        order_by_column := 'udpate_time';
        order_by_direction := 'DESC';    
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    END IF;

    -- Execute the query dynamically with pagination and role-based branch filter
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        branch_filter, branch_filter,  
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data1"("advisor_name" character varying DEFAULT NULL::character varying, "pic" character varying DEFAULT NULL::character varying, "branch" character varying DEFAULT NULL::character varying, "ticket_status" character varying DEFAULT NULL::character varying, "lead_type" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "sort_order" character varying DEFAULT NULL::character varying, "limit_rows" character varying DEFAULT '3'::character varying, "offset_rows" character varying DEFAULT '0'::character varying, "authrole" character varying DEFAULT 'User'::character varying, "authbranch" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    order_by_column VARCHAR;
    order_by_direction VARCHAR;
    branch_filter VARCHAR;
BEGIN
    -- Convert string 'Null' to actual NULL
    advisor_name := NULLIF(advisor_name, 'Null');
    pic := NULLIF(pic, 'Null');
    branch := NULLIF(branch, 'Null');
    ticket_status := NULLIF(ticket_status, 'Null');
    lead_type := NULLIF(lead_type, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    authbranch := NULLIF(authbranch, 'Null');

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;
    ELSE
        branch_filter := NULL;
    END IF;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'updated - newest to oldest' THEN
        order_by_column := 'update_time';
        order_by_direction := 'DESC';    
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    END IF;

    -- Execute the query dynamically with pagination and role-based branch filter
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_date, from_date, 
        to_date, to_date, 
        branch_filter, branch_filter,  
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data2"("advisor_name" character varying DEFAULT NULL::character varying, "pic" character varying DEFAULT NULL::character varying, "branch" character varying DEFAULT NULL::character varying, "ticket_status" character varying DEFAULT NULL::character varying, "lead_type" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "authrole" character varying DEFAULT 'User'::character varying, "authbranch" character varying DEFAULT NULL::character varying) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result INT;
    from_timestamp TIMESTAMP;
    to_timestamp TIMESTAMP;
    branch_filter VARCHAR;
BEGIN
    -- Convert string 'Null' to actual NULL
    advisor_name := NULLIF(advisor_name, 'Null');
    pic := NULLIF(pic, 'Null');
    branch := NULLIF(branch, 'Null');
    ticket_status := NULLIF(ticket_status, 'Null');
    lead_type := NULLIF(lead_type, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    authbranch := NULLIF(authbranch, 'Null');

    -- Convert input dates to timestamps, treating NULL as NULL
    from_timestamp := NULLIF(from_date, 'null')::TIMESTAMP;
    to_timestamp := NULLIF(to_date, 'null')::TIMESTAMP;

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;
    ELSE
        branch_filter := NULL;
    END IF;

    -- Execute the query dynamically to return count
    EXECUTE format(
        'SELECT COUNT(*) FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L);',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_timestamp, from_timestamp, 
        to_timestamp, to_timestamp, 
        branch_filter, branch_filter
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data2"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "authrole" character varying, "authbranch" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_data_3"("advisor_name" character varying DEFAULT NULL::character varying, "pic" character varying DEFAULT NULL::character varying, "branch" character varying DEFAULT NULL::character varying, "ticket_status" character varying DEFAULT NULL::character varying, "lead_type" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "sort_order" character varying DEFAULT NULL::character varying, "limit_rows" character varying DEFAULT '3'::character varying, "offset_rows" character varying DEFAULT '0'::character varying, "authrole" character varying DEFAULT 'User'::character varying, "authbranch" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    order_by_column VARCHAR;
    order_by_direction VARCHAR;
    branch_filter VARCHAR;
BEGIN
    -- Convert string 'Null' to actual NULL
    advisor_name := NULLIF(advisor_name, 'Null');
    pic := NULLIF(pic, 'Null');
    branch := NULLIF(branch, 'Null');
    ticket_status := NULLIF(ticket_status, 'Null');
    lead_type := NULLIF(lead_type, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    authbranch := NULLIF(authbranch, 'Null');

    -- Handle branch filtering based on role
    IF authrole = 'Admin' THEN
        branch_filter := authbranch;
    ELSE
        branch_filter := NULL;
    END IF;

    -- Determine sorting column and direction
    IF sort_order = 'created - oldest to newest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'created - newest to oldest' THEN
        order_by_column := 'created_at';
        order_by_direction := 'DESC';
    ELSIF sort_order = 'updated - oldest to newest' THEN
        order_by_column := 'udpate_time';
        order_by_direction := 'ASC';
    ELSIF sort_order = 'updated -newest to oldest' THEN
        order_by_column := 'udpate_time';
        order_by_direction := 'DESC';    
    ELSE
        order_by_column := 'update_time';
        order_by_direction := 'ASC';
    END IF;

    -- Execute the query dynamically with pagination and role-based branch filter
    EXECUTE format(
        'SELECT json_agg(t) FROM ( 
            SELECT * FROM "Master"
            WHERE (%L IS NULL OR "advisor_name" = %L)
            AND (%L IS NULL OR "pic" = %L)
            AND (%L IS NULL OR "branch" = %L)
            AND (%L IS NULL OR "ticket_status" = %L)
            AND (%L IS NULL OR "lead_type" = %L)
            AND (%L IS NULL OR "service_type" = %L)
            AND (%L IS NULL OR "created_at" >= %L)
            AND (%L IS NULL OR "created_at" <= %L)
            AND (%L IS NULL OR "branch" = %L)
            ORDER BY %I %s
            LIMIT %s OFFSET %s
        ) t;',
        advisor_name, advisor_name, 
        pic, pic, 
        branch, branch, 
        ticket_status, ticket_status, 
        lead_type, lead_type, 
        service_type, service_type, 
        from_date, from_date, 
        to_date, to_date, 
        branch_filter, branch_filter,  
        order_by_column, order_by_direction,
        limit_rows, offset_rows
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_data_3"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying DEFAULT NULL::character varying, "from_date_input" "date" DEFAULT NULL::"date", "to_date_input" "date" DEFAULT NULL::"date", "service_type_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_build_object(
        'Total count', COUNT(*),
        'Target Lead', COUNT(*) FILTER (WHERE ticket_status = 'Target Lead'),
        'Hot Lead', COUNT(*) FILTER (WHERE ticket_status = 'Hot Lead'),
        'Cold Lead', COUNT(*) FILTER (WHERE ticket_status = 'Cold Lead'),
        'Conversion', COUNT(*) FILTER (WHERE ticket_status = 'Conversion'),
        'Out of Reach', COUNT(*) FILTER (WHERE ticket_status = 'Out of Reach'),
        'Reconnect', COUNT(*) FILTER (WHERE ticket_status = 'Reconnect'),
        'Lead Closed', COUNT(*) FILTER (WHERE ticket_status = 'Lead Closed'),
        'Confirmed', COUNT(*) FILTER (WHERE ticket_status = 'Confirmed')
    )
    INTO result
    FROM "Master"
    WHERE 
        (branch_input IS NULL OR branch = branch_input) AND
        (from_date_input IS NULL OR created_at >= from_date_input) AND
        (to_date_input IS NULL OR created_at <= to_date_input) AND
        (service_type_input IS NULL OR service_type = service_type_input);

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" "date", "to_date_input" "date", "service_type_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying DEFAULT NULL::character varying, "from_date_input" character varying DEFAULT NULL::character varying, "to_date_input" character varying DEFAULT NULL::character varying, "service_type_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    branch_filter VARCHAR;
    service_filter VARCHAR;
    from_date DATE;
    to_date DATE;
BEGIN
    -- Handle 'Null' string conversion to actual NULLs
    branch_filter := NULLIF(lower(branch_input), 'null');
    service_filter := NULLIF(lower(service_type_input), 'null');

    from_date := CASE 
        WHEN lower(from_date_input) = 'null' THEN NULL
        ELSE from_date_input::DATE
    END;

    to_date := CASE 
        WHEN lower(to_date_input) = 'null' THEN NULL
        ELSE to_date_input::DATE
    END;

    -- Main query
    SELECT json_build_object(
        'Total count', COUNT(*),
        'Target Lead', COUNT(*) FILTER (WHERE ticket_status = 'Target Lead'),
        'Hot Lead', COUNT(*) FILTER (WHERE ticket_status = 'Hot Lead'),
        'Cold Lead', COUNT(*) FILTER (WHERE ticket_status = 'Cold Lead'),
        'Conversion', COUNT(*) FILTER (WHERE ticket_status = 'Conversion'),
        'Out of Reach', COUNT(*) FILTER (WHERE ticket_status = 'Out of Reach'),
        'Reconnect', COUNT(*) FILTER (WHERE ticket_status = 'Reconnect'),
        'Lead Closed', COUNT(*) FILTER (WHERE ticket_status = 'Lead Closed'),
        'Confirmed', COUNT(*) FILTER (WHERE ticket_status = 'Confirmed')
    )
    INTO result
    FROM "Master"
    WHERE 
        (branch_filter IS NULL OR branch = branch_filter) AND
        (from_date IS NULL OR created_at >= from_date) AND
        (to_date IS NULL OR created_at <= to_date) AND
        (service_filter IS NULL OR service_type = service_filter);

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying DEFAULT NULL::character varying, "from_date_input" character varying DEFAULT NULL::character varying, "to_date_input" character varying DEFAULT NULL::character varying, "service_type_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    branch_filter VARCHAR;
    service_filter VARCHAR;
    from_date DATE;
    to_date DATE;
BEGIN
    -- Convert 'Null' string values to actual NULLs
    branch_filter := NULLIF(branch_input, 'Null');
    service_filter := NULLIF(service_type_input, 'Null');
    from_date := NULLIF(from_date_input, 'Null')::DATE;
    to_date := NULLIF(to_date_input, 'Null')::DATE;

    -- Main aggregation query
    SELECT json_build_object(
        'Total count', COUNT(*),
        'Target Lead', COUNT(*) FILTER (WHERE ticket_status = 'Target Lead'),
        'Hot Lead', COUNT(*) FILTER (WHERE ticket_status = 'Hot Lead'),
        'Cold Lead', COUNT(*) FILTER (WHERE ticket_status = 'Cold Lead'),
        'Conversion', COUNT(*) FILTER (WHERE ticket_status = 'Conversion'),
        'Out of Reach', COUNT(*) FILTER (WHERE ticket_status = 'Out of Reach'),
        'Reconnect', COUNT(*) FILTER (WHERE ticket_status = 'Reconnect'),
        'Lead Closed', COUNT(*) FILTER (WHERE ticket_status = 'Lead Closed'),
        'Confirmed', COUNT(*) FILTER (WHERE ticket_status = 'Confirmed')
    )
    INTO result
    FROM "Master"
    WHERE 
        (branch_filter IS NULL OR branch = branch_filter) AND
        (from_date IS NULL OR created_at >= from_date) AND
        (to_date IS NULL OR created_at <= to_date) AND
        (service_filter IS NULL OR service_type = service_filter);

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying DEFAULT NULL::character varying, "from_date_input" character varying DEFAULT NULL::character varying, "to_date_input" character varying DEFAULT NULL::character varying, "service_type_input" character varying DEFAULT NULL::character varying, "role_input" character varying DEFAULT NULL::character varying, "branch1_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    effective_branch VARCHAR;
    service_filter VARCHAR;
    from_date DATE;
    to_date DATE;
BEGIN
    -- Convert string 'Null' to actual NULLs
    service_filter := NULLIF(service_type_input, 'Null');
    from_date := NULLIF(from_date_input, 'Null')::DATE;
    to_date := NULLIF(to_date_input, 'Null')::DATE;

    -- Determine effective branch filter based on role
    IF lower(role_input) = 'admin' THEN
        effective_branch := NULLIF(branch1_input, 'Null');
    ELSE
        effective_branch := NULLIF(branch_input, 'Null');
    END IF;

    -- Main aggregation query
    SELECT json_build_object(
        'TotalCount', COUNT(*),
        'TargetLead', COUNT(*) FILTER (WHERE ticket_status = 'Target Lead'),
        'HotLead', COUNT(*) FILTER (WHERE ticket_status = 'Hot Lead'),
        'ColdLead', COUNT(*) FILTER (WHERE ticket_status = 'Cold Lead'),
        'Conversion', COUNT(*) FILTER (WHERE ticket_status = 'Conversion'),
        'OutOfReach', COUNT(*) FILTER (WHERE ticket_status = 'Out of Reach'),
        'Reconnect', COUNT(*) FILTER (WHERE ticket_status = 'Reconnect'),
        'LeadClosed', COUNT(*) FILTER (WHERE ticket_status = 'Lead Closed'),
        'Confirmed', COUNT(*) FILTER (WHERE ticket_status = 'Confirmed')
    )
    INTO result
    FROM "Master"
    WHERE 
        (effective_branch IS NULL OR branch = effective_branch) AND
        (from_date IS NULL OR created_at >= from_date) AND
        (to_date IS NULL OR created_at <= to_date) AND
        (service_filter IS NULL OR service_type = service_filter);

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying, "role_input" character varying, "branch1_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_ticket_status_summary2"("branch_input" character varying DEFAULT NULL::character varying, "from_date_input" character varying DEFAULT NULL::character varying, "to_date_input" character varying DEFAULT NULL::character varying, "pic_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    branch_filter VARCHAR;
    pic_filter VARCHAR;
    from_date DATE;
    to_date DATE;
BEGIN
    -- Convert string 'Null' to actual NULLs
    branch_filter := NULLIF(branch_input, 'Null');
    pic_filter := NULLIF(pic_input, 'Null');
    from_date := NULLIF(from_date_input, 'Null')::DATE;
    to_date := NULLIF(to_date_input, 'Null')::DATE;

    -- Main aggregation query
    SELECT json_build_object(
        'TotalCount', COUNT(*),
        'TargetLead', COUNT(*) FILTER (WHERE ticket_status = 'Target Lead'),
        'HotLead', COUNT(*) FILTER (WHERE ticket_status = 'Hot Lead'),
        'ColdLead', COUNT(*) FILTER (WHERE ticket_status = 'Cold Lead'),
        'Conversion', COUNT(*) FILTER (WHERE ticket_status = 'Conversion'),
        'OutOfReach', COUNT(*) FILTER (WHERE ticket_status = 'Out of Reach'),
        'Reconnect', COUNT(*) FILTER (WHERE ticket_status = 'Reconnect'),
        'LeadClosed', COUNT(*) FILTER (WHERE ticket_status = 'Lead Closed'),
        'Confirmed', COUNT(*) FILTER (WHERE ticket_status = 'Confirmed')
    )
    INTO result
    FROM "Master"
    WHERE 
        (branch_filter IS NULL OR branch = branch_filter) AND
        (from_date IS NULL OR created_at >= from_date) AND
        (to_date IS NULL OR created_at <= to_date) AND
        (pic_filter IS NULL OR pic = pic_filter);

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_master_ticket_status_summary2"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "pic_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_clickdent_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if NEW.service_type = 'ClickDent' then

    -- Check and process each image only if it is not null or empty
    if NEW.dent_image_1 is not null and NEW.dent_image_1 <> '' then
      perform call_damage_detection(NEW.id, NEW.dent_image_1);
    end if;

    if NEW.dent_image_2 is not null and NEW.dent_image_2 <> '' then
      perform call_damage_detection(NEW.id, NEW.dent_image_2);
    end if;

    if NEW.dent_image_3 is not null and NEW.dent_image_3 <> '' then
      perform call_damage_detection(NEW.id, NEW.dent_image_3);
    end if;

    if NEW.dent_image_4 is not null and NEW.dent_image_4 <> '' then
      perform call_damage_detection(NEW.id, NEW.dent_image_4);
    end if;

    if NEW.dent_image_5 is not null and NEW.dent_image_5 <> '' then
      perform call_damage_detection(NEW.id, NEW.dent_image_5);
    end if;

  end if;

  return NEW;
end;
$$;


ALTER FUNCTION "public"."handle_clickdent_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation"("branch" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');

    EXECUTE format(
        'SELECT COALESCE(json_agg(t), ''[]''::json) FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')
            AND (%L IS NULL OR branch = %L)
            AND (%L IS NULL OR service_type = %L)
            AND (%L IS NULL OR udpate_time >= %L::timestamp)
            AND (%L IS NULL OR udpate_time <= %L::timestamp)
            ORDER BY id ASC
        ) t;',
        branch, branch,
        service_type, service_type,
        from_date, from_date,
        to_date, to_date
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation"("branch" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "insurance_false" character varying DEFAULT NULL::character varying, "fc_false" character varying DEFAULT NULL::character varying, "emission_false" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    insurance_false := NULLIF(insurance_false, 'Null');
    fc_false := NULLIF(fc_false, 'Null');
    emission_false := NULLIF(emission_false, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(t), ''[]''::json)
        FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')';

    -- Dynamically build WHERE clauses
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND branch = %L', branch);
    END IF;

    IF service_type IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND service_type = %L', service_type);

        -- Add filters if service_type is ClickPolicy
        IF service_type = 'ClickPolicy' THEN
            IF insurance_false = 'true' THEN
                where_clauses := where_clauses || ' AND "Insurance_Recommended" = ''false''';
            END IF;
            IF fc_false = 'true' THEN
                where_clauses := where_clauses || ' AND "Fc_Recommended" = ''false''';
            END IF;
            IF emission_false = 'true' THEN
                where_clauses := where_clauses || ' AND "Emission_Recommended" = ''false''';
            END IF;
        END IF;
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time <= %L::timestamp', to_date);
    END IF;

    base_query := base_query || where_clauses || ' ORDER BY id ASC) t;';

    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" character varying, "fc_false" character varying, "emission_false" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation1"("branch" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');

    EXECUTE format(
        'SELECT COALESCE(json_agg(t), ''[]''::json) FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')
            AND (%L IS NULL OR branch = %L)
            AND (%L IS NULL OR service_type = %L)
            AND (%L IS NULL OR udpate_time >= %L::timestamp)
            AND (%L IS NULL OR udpate_time <= %L::timestamp)
            ORDER BY id ASC
        ) t;',
        branch, branch,
        service_type, service_type,
        from_date, from_date,
        to_date, to_date
    ) INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation1"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_dent"("branch" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(m), ''[]''::json)
        FROM (
            SELECT * FROM "Master" m
            WHERE m.ticket_status IN (''Hot Lead'', ''Follow Up'')
              AND m.service_type = ''ClickDent''
              AND m.id IN (
                  SELECT lead_id
                  FROM "DentDetection_Damage"
                  WHERE is_damaged = ''true''
                  GROUP BY lead_id
                  HAVING COUNT(*) > 0
              )
    ';

    -- Optional filters
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.branch = %L', branch);
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.udpate_time <= %L::timestamp', to_date);
    END IF;

    -- Complete query
    base_query := base_query || where_clauses || ' ORDER BY m.id ASC) m;';

    -- Execute
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_dent"("branch" character varying, "from_date" character varying, "to_date" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_dent1"("branch" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "car_number" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    car_number := NULLIF(car_number, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(m), ''[]''::json)
        FROM (
            SELECT * FROM "Master" m
            WHERE m.ticket_status IN (''Hot Lead'', ''Follow Up'')
              AND m.service_type = ''ClickDent''
              AND m.id IN (
                  SELECT lead_id
                  FROM "DentDetection_Damage"
                  WHERE is_damaged = ''true''
                  GROUP BY lead_id
                  HAVING COUNT(*) > 0
              )
    ';

    -- Optional filters
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.branch = %L', branch);
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.udpate_time <= %L::timestamp', to_date);
    END IF;

    -- Car number search filter
    IF car_number IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND m.car_number ILIKE %L', '%' || car_number || '%');
    END IF;

    -- Complete query
    base_query := base_query || where_clauses || ' ORDER BY m.id ASC) m;';

    -- Execute
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_dent1"("branch" character varying, "from_date" character varying, "to_date" character varying, "car_number" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_policy"("branch" character varying DEFAULT NULL::character varying, "service_type" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "insurance_false" boolean DEFAULT NULL::boolean, "fc_false" boolean DEFAULT NULL::boolean, "emission_false" boolean DEFAULT NULL::boolean) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    service_type := NULLIF(service_type, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(t), ''[]''::json)
        FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')';

    -- Dynamically build WHERE clauses
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND branch = %L', branch);
    END IF;

    IF service_type IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND service_type = %L', service_type);

        -- Add conditional filters only for 'ClickPolicy'
        IF service_type = 'ClickPolicy' THEN
            IF insurance_false THEN
                where_clauses := where_clauses || ' AND "Insurance_Recommended" = false';
            END IF;
            IF fc_false THEN
                where_clauses := where_clauses || ' AND "Fc_Recommended" = false';
            END IF;
            IF emission_false THEN
                where_clauses := where_clauses || ' AND "Emission_Recommended" = false';
            END IF;
        END IF;
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time <= %L::timestamp', to_date);
    END IF;

    -- Finish query
    base_query := base_query || where_clauses || ' ORDER BY id ASC) t;';

    -- Execute final query
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_policy"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" boolean, "fc_false" boolean, "emission_false" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_policy1"("branch" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "recommend_input" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    recommend_input := LOWER(NULLIF(recommend_input, 'Null'));  -- Normalize case

    base_query := '
        SELECT COALESCE(json_agg(t), ''[]''::json)
        FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')
            AND service_type = ''ClickPolicy''';  -- Fixed value

    -- Optional filters
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND branch = %L', branch);
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time <= %L::timestamp', to_date);
    END IF;

    -- Conditional recommended filters
    IF recommend_input = 'insurance' THEN
        where_clauses := where_clauses || ' AND "Insurance_Recommended" = ''false''';
    ELSIF recommend_input = 'emission' THEN
        where_clauses := where_clauses || ' AND "Emission_Recommended" = ''false''';
    ELSIF recommend_input = 'fc' THEN
        where_clauses := where_clauses || ' AND "Fc_Recommended" = ''false''';
    END IF;

    -- Complete query
    base_query := base_query || where_clauses || ' ORDER BY id ASC) t;';

    -- Execute
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_policy1"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_policy2"("branch" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "recommend_input" character varying DEFAULT NULL::character varying, "search_car_number" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    recommend_input := LOWER(NULLIF(recommend_input, 'Null'));
    search_car_number := NULLIF(search_car_number, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(t), ''[]''::json)
        FROM (
            SELECT * FROM "Master"
            WHERE 1=1';

    -- If car number is provided, ignore all other filters
    IF search_car_number IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND car_number ILIKE %L', '%' || search_car_number || '%');
    ELSE
        -- Existing filters when car number is NOT provided
        where_clauses := where_clauses || ' AND ticket_status IN (''Hot Lead'', ''Follow Up'')';
        where_clauses := where_clauses || ' AND service_type = ''ClickPolicy''';

        IF branch IS NOT NULL THEN
            where_clauses := where_clauses || format(' AND branch = %L', branch);
        END IF;

        IF from_date IS NOT NULL THEN
            where_clauses := where_clauses || format(' AND udpate_time >= %L::timestamp', from_date);
        END IF;

        IF to_date IS NOT NULL THEN
            where_clauses := where_clauses || format(' AND udpate_time <= %L::timestamp', to_date);
        END IF;

        IF recommend_input = 'insurance' THEN
            where_clauses := where_clauses || ' AND "Insurance_Recommended" = ''false''';
        ELSIF recommend_input = 'emission' THEN
            where_clauses := where_clauses || ' AND "Emission_Recommended" = ''false''';
        ELSIF recommend_input = 'fc' THEN
            where_clauses := where_clauses || ' AND "Fc_Recommended" = ''false''';
        END IF;
    END IF;

    -- Final query
    base_query := base_query || where_clauses || ' ORDER BY id ASC) t;';

    -- Execute
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_policy2"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "search_car_number" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recommendation_policy3"("branch" character varying DEFAULT NULL::character varying, "from_date" character varying DEFAULT NULL::character varying, "to_date" character varying DEFAULT NULL::character varying, "recommend_input" character varying DEFAULT NULL::character varying, "car_number" character varying DEFAULT NULL::character varying) RETURNS "json"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    result JSON;
    base_query TEXT;
    where_clauses TEXT := '';
BEGIN
    -- Convert 'Null' strings to actual NULLs
    branch := NULLIF(branch, 'Null');
    from_date := NULLIF(from_date, 'Null');
    to_date := NULLIF(to_date, 'Null');
    recommend_input := LOWER(NULLIF(recommend_input, 'Null'));
    car_number := NULLIF(car_number, 'Null');

    base_query := '
        SELECT COALESCE(json_agg(t), ''[]''::json)
        FROM (
            SELECT * FROM "Master"
            WHERE ticket_status IN (''Hot Lead'', ''Follow Up'')
            AND service_type = ''ClickPolicy''';

    -- Optional filters
    IF branch IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND branch = %L', branch);
    END IF;

    IF from_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time >= %L::timestamp', from_date);
    END IF;

    IF to_date IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND udpate_time <= %L::timestamp', to_date);
    END IF;

    -- Conditional recommended filters
    IF recommend_input = 'insurance' THEN
        where_clauses := where_clauses || ' AND "Insurance_Recommended" = ''false''';
    ELSIF recommend_input = 'emission' THEN
        where_clauses := where_clauses || ' AND "Emission_Recommended" = ''false''';
    ELSIF recommend_input = 'fc' THEN
        where_clauses := where_clauses || ' AND "Fc_Recommended" = ''false''';
    END IF;

    -- Car number filter
    IF car_number IS NOT NULL THEN
        where_clauses := where_clauses || format(' AND car_number ILIKE %L', '%' || car_number || '%');
    END IF;

    -- Complete query
    base_query := base_query || where_clauses || ' ORDER BY id ASC) t;';

    -- Execute
    EXECUTE base_query INTO result;

    RETURN result;
END;
$$;


ALTER FUNCTION "public"."recommendation_policy3"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "car_number" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."truncate_update_time"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
    update "Master"
    set udpate_time = date_trunc('day', udpate_time)
    where udpate_time::time != '00:00:00'::time;  -- update only if not already truncated
end;
$$;


ALTER FUNCTION "public"."truncate_update_time"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."Admin Details" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "access" "text",
    "branch" "text",
    "email" "text",
    "role" "text"
);


ALTER TABLE "public"."Admin Details" OWNER TO "postgres";


ALTER TABLE "public"."Admin Details" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Admin Details_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Damage Levels" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lead_id" bigint,
    "mid_bonnet_hood" "text",
    "mid_front_windshield" "text",
    "mid_leftA_pillar" "text",
    "mid_rightA_pillar" "text",
    "mid_left_front_window" "text",
    "mid_right_front_window" "text",
    "mid_left_B_pillar" "text",
    "mid_right_B_pillar" "text",
    "mid_roof" "text",
    "mid_left_rear_window" "text",
    "mid_right_rear_window" "text",
    "mid_leftC_pillar" "text",
    "mid_rightC_pillar" "text",
    "mid_rear_windshield" "text",
    "mid_trunk_hood" "text",
    "top_front_spoiler" "text",
    "top_front_bumper" "text",
    "top_grille" "text",
    "top_left_front_headlight" "text",
    "top_left_front_foglight" "text",
    "top_right_front_headlight" "text",
    "top_right_front_foglight" "text",
    "bottom_end_panel" "text",
    "bottom_rear_bumper" "text",
    "bottom_rear_spoiler" "text",
    "bottom_left_rear_taillight" "text",
    "bottom_right_rear_taillight" "text",
    "bottom_spare_wheel" "text",
    "left_front_fender" "text",
    "left_front_door" "text",
    "left_rear_door" "text",
    "left_rocker_panel" "text",
    "left_rear_fender" "text",
    "left_front_wheel_disc" "text",
    "left_rear_wheel_disc" "text",
    "right_front_fender" "text",
    "right_front_door" "text",
    "right_rear_door" "text",
    "right_rocker_panel" "text",
    "right_rear_fender" "text",
    "right_front_wheel_disc" "text",
    "right_rear_wheel_disc" "text",
    "left_mirror" "text",
    "right_mirror" "text"
);


ALTER TABLE "public"."Damage Levels" OWNER TO "postgres";


COMMENT ON TABLE "public"."Damage Levels" IS 'Contains damage info for each lead';



ALTER TABLE "public"."Damage Levels" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Damage Levels_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."DentDetection_Damage" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lead_id" integer,
    "image_url" "text",
    "damage_json" "jsonb",
    "is_damaged" "text"
);


ALTER TABLE "public"."DentDetection_Damage" OWNER TO "postgres";


ALTER TABLE "public"."DentDetection_Damage" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."DentDetection_Damage_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Master" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "car_number" "text" DEFAULT ''::"text" NOT NULL,
    "lead_type" "text",
    "car_make" "text",
    "car_model" "text",
    "customer_name" "text",
    "customer_mobile" "text",
    "dent_notes" "text",
    "dent_image_1" "text",
    "dent_image_2" "text",
    "dent_image_3" "text",
    "dent_image_4" "text",
    "dent_image_5" "text",
    "policy_issued_by" "text",
    "insurance_expiry_date" "date",
    "fc_expiry_date" "date",
    "emission_test_expiry_date" "date",
    "policy_notes" "text",
    "policy_image_1" "text",
    "policy_image_2" "text",
    "fl_tread_depth" "text",
    "fr_tread_depth" "text",
    "rl_tread_depth" "text",
    "rr_tread_depth" "text",
    "fl_tyre_brand" "text",
    "fr_tyre_brand" "text",
    "rl_tyre_brand" "text",
    "rr_tyre_brand" "text",
    "fl_dot_code" "text",
    "fr_dot_code" "text",
    "rl_dot_code" "text",
    "rr_dot_code" "text",
    "tyre_notes" "text",
    "tyre_image_1" "text",
    "tyre_image_2" "text",
    "tyre_image_3" "text",
    "tyre_image_4" "text",
    "spare_tread_depth" "text",
    "spare_tyre_brand" "text",
    "spare_dot_code" "text",
    "service_type" "text",
    "ticket_status" "text",
    "advisor_id" "text",
    "advisor_name" "text",
    "car_color" "text",
    "car_color_code" "text",
    "car_board" "text",
    "vin_number" "text",
    "chassis_number" "text",
    "engine_number" "text",
    "car_reg_year" "text",
    "car_reg_month" "text",
    "car_ownership" "text",
    "extended_warranty_expiry_date" "date",
    "last_service_history" "text",
    "customer_email" "text",
    "customer_alternate_contact" "text",
    "branch" "text",
    "pic" "text",
    "secondary_pic" "text",
    "payment_options" "text",
    "status_change_reason" "text",
    "status_change_notes" "text",
    "is_duplicate" boolean,
    "lead_notes" "text",
    "udpate_time" timestamp with time zone,
    "testing" "date",
    "DateAndTime" character varying,
    "insuranceProvider_attestr" character varying,
    "make_attestr" character varying,
    "model_attestr" character varying,
    "colortype_attestr" character varying,
    "Insurance_Expiry_attestr" "text",
    "Emission_Test_Expiry_attestr" "text",
    "FC_Date_attestr" "text",
    "odometer_reading" bigint,
    "Insurance_policy_number" "text",
    "revenue" bigint,
    "Car_Damage" "text",
    "Insurance_Recommended" "text",
    "Emission_Recommended" "text",
    "Fc_Recommended" "text",
    "insurence_protect" "text"
);


ALTER TABLE "public"."Master" OWNER TO "postgres";


COMMENT ON TABLE "public"."Master" IS 'Holds lead information';



COMMENT ON COLUMN "public"."Master"."advisor_id" IS 'unique id of the advisor that captured the information';



ALTER TABLE "public"."Master" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Master_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."carmake" (
    "make" "text" NOT NULL
);


ALTER TABLE "public"."carmake" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."carmodel" (
    "make" "text",
    "model" "text" NOT NULL
);


ALTER TABLE "public"."carmodel" OWNER TO "postgres";


ALTER TABLE ONLY "public"."Admin Details"
    ADD CONSTRAINT "Admin Details_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Damage Levels"
    ADD CONSTRAINT "Damage Levels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."DentDetection_Damage"
    ADD CONSTRAINT "DentDetection_Damage_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Master"
    ADD CONSTRAINT "Master_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."carmake"
    ADD CONSTRAINT "carmake_pkey" PRIMARY KEY ("make");



ALTER TABLE ONLY "public"."carmodel"
    ADD CONSTRAINT "carmodel_pkey" PRIMARY KEY ("model");



CREATE OR REPLACE TRIGGER "damage" AFTER INSERT ON "public"."Master" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://bpzywmkxfihhktjqoiqr.supabase.co/functions/v1/damagedetection', 'POST', '{"Content-type":"application/json"}', '{}', '10000');



CREATE OR REPLACE TRIGGER "dent_damage_insert_trigger" AFTER INSERT ON "public"."DentDetection_Damage" FOR EACH ROW EXECUTE FUNCTION "public"."dent_damage_webhook"();



ALTER TABLE ONLY "public"."Damage Levels"
    ADD CONSTRAINT "Damage Levels_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."Master"("id");





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."Damage Levels";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."DentDetection_Damage";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."Master";









GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";









































































































































































































GRANT ALL ON FUNCTION "public"."dent_damage_webhook"() TO "anon";
GRANT ALL ON FUNCTION "public"."dent_damage_webhook"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."dent_damage_webhook"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_advisor_summary"("advisor_name_input" "text", "branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_advisor_summary"("advisor_name_input" "text", "branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_advisor_summary"("advisor_name_input" "text", "branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_branch_advisors_summary"("branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_branch_advisors_summary"("branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_branch_advisors_summary"("branch_input" "text", "start_date_input" "text", "end_date_input" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_filtered_master_data"("p_advisor_name" "text", "p_pic" "text", "p_branch" "text", "p_ticket_status" "text", "p_lead_type" "text", "p_service_type" "text", "p_auth_role" "text", "p_auth_branch" "text", "p_from_date" "text", "p_to_date" "text", "p_sort_order" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_filtered_master_data"("p_advisor_name" "text", "p_pic" "text", "p_branch" "text", "p_ticket_status" "text", "p_lead_type" "text", "p_service_type" "text", "p_auth_role" "text", "p_auth_branch" "text", "p_from_date" "text", "p_to_date" "text", "p_sort_order" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_filtered_master_data"("p_advisor_name" "text", "p_pic" "text", "p_branch" "text", "p_ticket_status" "text", "p_lead_type" "text", "p_service_type" "text", "p_auth_role" "text", "p_auth_branch" "text", "p_from_date" "text", "p_to_date" "text", "p_sort_order" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer, "authrole" "text", "authbranch" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer, "authrole" "text", "authbranch" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer, "authrole" "text", "authbranch" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "authrole" "text", "authbranch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "authrole" "text", "authbranch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" "text", "pic" "text", "branch" "text", "authrole" "text", "authbranch" "text", "ticket_status" "text", "lead_type" "text", "service_type" "text", "from_date" "text", "to_date" "text", "sort_order" "text", "limit_rows" integer, "offset_rows" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" integer, "offset_rows" integer, "authrole" character varying, "authbranch" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data1"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data2"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "authrole" character varying, "authbranch" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data2"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "authrole" character varying, "authbranch" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data2"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "authrole" character varying, "authbranch" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_data_3"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_data_3"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_data_3"("advisor_name" character varying, "pic" character varying, "branch" character varying, "ticket_status" character varying, "lead_type" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "sort_order" character varying, "limit_rows" character varying, "offset_rows" character varying, "authrole" character varying, "authbranch" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" "date", "to_date_input" "date", "service_type_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" "date", "to_date_input" "date", "service_type_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" "date", "to_date_input" "date", "service_type_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying, "role_input" character varying, "branch1_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying, "role_input" character varying, "branch1_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary1"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "service_type_input" character varying, "role_input" character varying, "branch1_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary2"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "pic_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary2"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "pic_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_ticket_status_summary2"("branch_input" character varying, "from_date_input" character varying, "to_date_input" character varying, "pic_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_clickdent_insert"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_clickdent_insert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_clickdent_insert"() TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" character varying, "fc_false" character varying, "emission_false" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" character varying, "fc_false" character varying, "emission_false" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" character varying, "fc_false" character varying, "emission_false" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation1"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation1"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation1"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_dent"("branch" character varying, "from_date" character varying, "to_date" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_dent"("branch" character varying, "from_date" character varying, "to_date" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_dent"("branch" character varying, "from_date" character varying, "to_date" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_dent1"("branch" character varying, "from_date" character varying, "to_date" character varying, "car_number" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_dent1"("branch" character varying, "from_date" character varying, "to_date" character varying, "car_number" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_dent1"("branch" character varying, "from_date" character varying, "to_date" character varying, "car_number" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_policy"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" boolean, "fc_false" boolean, "emission_false" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_policy"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" boolean, "fc_false" boolean, "emission_false" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_policy"("branch" character varying, "service_type" character varying, "from_date" character varying, "to_date" character varying, "insurance_false" boolean, "fc_false" boolean, "emission_false" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_policy1"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_policy1"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_policy1"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_policy2"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "search_car_number" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_policy2"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "search_car_number" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_policy2"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "search_car_number" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."recommendation_policy3"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "car_number" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."recommendation_policy3"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "car_number" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."recommendation_policy3"("branch" character varying, "from_date" character varying, "to_date" character varying, "recommend_input" character varying, "car_number" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."truncate_update_time"() TO "anon";
GRANT ALL ON FUNCTION "public"."truncate_update_time"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."truncate_update_time"() TO "service_role";
























GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Admin Details" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Admin Details" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Admin Details" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Admin Details_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Admin Details_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Admin Details_id_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Damage Levels" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Damage Levels" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Damage Levels" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Damage Levels_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Damage Levels_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Damage Levels_id_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."DentDetection_Damage" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."DentDetection_Damage" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."DentDetection_Damage" TO "service_role";



GRANT ALL ON SEQUENCE "public"."DentDetection_Damage_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."DentDetection_Damage_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."DentDetection_Damage_id_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Master" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Master" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."Master" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Master_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Master_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Master_id_seq" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmake" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmake" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmake" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmodel" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmodel" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE "public"."carmodel" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLES TO "service_role";






























RESET ALL;
