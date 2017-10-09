create or replace PACKAGE BODY partition_util_pkg
IS 
    --------------------------------------------------------------------------------------------------------------------------
    -- ver# date        Author/description
    -- ---- ----------- -------------------------------------------------------------------------------------------------------
    -- 1.0  2017_05_31  Pujit Koirala/Paul Healy - Initial version 440.227.9043
    --                  GM-1226 Story_3_of_N: pl/sql block to move partitions of tracker data from the live "tracker" to archive
    --
    ---------------------------------------------------------------------------------------------------------------------------



    PROCEDURE drop_empty_partition (in_table_name VARCHAR2, in_partition_name VARCHAR2)
    AS
        --------------------------------------------------------------------------------------------------------------------
        -- drop_empty_partition drops the partitions for the given table if present.Before it drops it checks if the partition is empty or not.
        --If partition is not empty it raise error
        --If the table doesn't exist then raise error,if partition doesn't exits then raise error
        --------------------------------------------------------------------------------------------------------------------

        v_count               NUMBER;
        v_droppartition_sql   VARCHAR2 (1000);
        v_sql                 VARCHAR2 (4000);
        v_in_partition_name   VARCHAR2 (6) := 'P1';
        v_table_exist         NUMBER := 1;
    BEGIN
        IF v_in_partition_name = in_partition_name THEN
            -- raise_application_error('NOT ALLOWED TO DROP PARTITION NAMED P1');
            raise_application_error (-20021, 'ERROR:NOT ALLOWED TO DROP PARTITION NAMED P1');
        END IF;

        SELECT COUNT (*)
        INTO v_table_exist
        FROM user_tables
        WHERE table_name = in_table_name;

        IF (v_table_exist != 1) THEN
            raise_application_error (-20022, 'ERROR: TABLE' || in_table_name || ' name doesn not exist');
        END IF;

        v_sql := ' select count(*) from ' || in_table_name || ' partition (' || in_partition_name || ')';

        EXECUTE IMMEDIATE v_sql INTO v_count;

        DBMS_OUTPUT.put_line (v_count);

        IF v_count = 0 THEN
            v_droppartition_sql := 'Alter table ' || ' ' || in_table_name || ' Drop Partition ' || in_partition_name;
            DBMS_OUTPUT.put_line (v_droppartition_sql);

            EXECUTE IMMEDIATE (v_droppartition_sql);
        ELSIF v_count >= 1 THEN
            raise_application_error (-20001, 'Error: partition is NOT empty hence we are NOT allowed to drop it');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF (SQLCODE = -02149) -- specified partition does not exist
                                 THEN
                NULL; -- its ok it doesn't exist return success
            ELSIF (SQLCODE = -00942) THEN
                raise_application_error (-200942, 'Error: ' || SQLERRM);
            ELSE
                raise_application_error (-20001, 'Error: ' || SQLERRM);
            END IF;
    END drop_empty_partition;
    
    
    
    

    PROCEDURE swap_partition_w_exch_tbl (in_table_name             VARCHAR2,
                                         in_partition_name         VARCHAR2,
                                         in_exchange_tbl_owner     VARCHAR2,
                                         in_exchange_table_name    VARCHAR2
                                        )
    AS
        --------------------------------------------------------------------------------------------------------------------
        -- swap_partition_w_exch_tbl will swap a partition and a stand alone exchange  tables.
        -- to move single partition from an existing partitioned table into a different partitioned table
        -- you would call this procedure twice, once to move the partition from the source into the standalone
        -- and then  again to move from the standalone into the target partitioned table.
        --------------------------------------------------------------------------------------------------------------------
        v_sql   VARCHAR2 (32000);
    BEGIN
        v_sql :=
               'ALTER TABLE '
            || in_table_name
            || ' EXCHANGE PARTITION '
            || in_partition_name
            || ' WITH TABLE '
            || in_exchange_tbl_owner
            || '.'
            || in_exchange_table_name
            || ' INCLUDING INDEXES WITHOUT VALIDATION';

        --DBMS_OUTPUT.put_line (v_sql);

        EXECUTE IMMEDIATE v_sql;
    END    swap_partition_w_exch_tbl;

 



    PROCEDURE return_partition_list (in_tablename VARCHAR, c_qry IN OUT SYS_REFCURSOR)
    AS
        --------------------------------------------------------------------------------------------------------------------
        -- return_partition_list  will list all the partitions present for the given table within the valid date range that can be archived based on our retention policy.
        --
        --------------------------------------------------------------------------------------------------------------------

        v_sql   VARCHAR2 (32767);
    BEGIN
        v_sql :=
               'WITH FIRST_RETAIN_DT
            AS (SELECT DT
            FROM (SELECT TO_CHAR (dt,''DY'') DY,MIN (DT) DT
               FROM (SELECT TRUNC (SYSDATE) - ROWNUM dt
                     FROM (SELECT NULL
                           FROM DUAL
                           CONNECT BY LEVEL <= 20))
               GROUP BY TO_CHAR (dt,''DY'')) MSTR
             WHERE DY = ''SUN'')
              SELECT
                  UTP.*
               -- TABLE_NAME,PARTITION_NAME,partition_util_pkg.get_dt_for_partition_name (utp.table_name,utp.partition_name) DT
              FROM user_tab_partitions  utp
              WHERE (partition_util_pkg.get_dt_for_partition_name (utp.table_name,utp.partition_name) ) < (SELECT DT FROM FIRST_RETAIN_DT)
              and partition_name not in (''P1'')
              AND TABLE_NAME = '''
            || in_tablename
            || '''
              order by partition_util_pkg.get_dt_for_partition_name (utp.table_name,utp.partition_name)';

        OPEN c_qry FOR v_sql;
    END return_partition_list;





    FUNCTION get_partition_name_for_dt (in_table_name VARCHAR2, in_dt DATE)
        RETURN VARCHAR2
    IS
        --------------------------------------------------------------------------------------------------------------------
        -- get_partition_name_for_dt assumes input table is interval partitioned,receive table_name and a date
        -- we return the partition name that that date would flow into.  This does not mean that partition already contains data for that date.
        -- for example if we are interval partioned and data is sparse we might have this situation...
        --
        --     table_name | partition_name | dt
        --     TRACKER   | SYS_P250348    | 5/19/2016 11:59:59 PM
        --     TRACKER   | SYS_P250351   |  8/6/2016 11:59:59 PM
        --
        --   in the example above may 19th data is in SYS_P250348   and everything between May20th thruh August 6th inclusive is in SYS_P250351
        --   if we are called with a random date between May20th thruh August 6th  we need to return SYS_P250351
        --------------------------------------------------------------------------------------------------------------------
        out_partition_name   VARCHAR2 (100) := '';
    BEGIN
        WITH partition_xml
             AS (SELECT DBMS_XMLGEN.getxmltype (
                               'select table_name,partition_name,high_value from user_tab_partitions where table_name = '''
                            || in_table_name
                            || '''')
                            AS x
                 FROM DUAL),
             partition_list
             AS (SELECT EXTRACTVALUE (rws.object_value, '/ROW/PARTITION_NAME') partition_name,
                        TO_DATE (
                            REPLACE (REPLACE (EXTRACTVALUE (rws.object_value, '/ROW/HIGH_VALUE'), 'TIMESTAMP'' ', ''),
                                     ' 00:00:00''',
                                     ''
                                    ),
                            'yyyy-mm-dd')
                            high_value
                 FROM partition_xml x, TABLE (XMLSEQUENCE (EXTRACT (x.x, '/ROWSET/ROW'))) rws)
        SELECT MIN (partition_name)
        INTO out_partition_name
        FROM partition_list
        WHERE TRUNC (high_value) > TRUNC (in_dt);

        RETURN (out_partition_name);
    END    get_partition_name_for_dt;





    PROCEDURE archive_active_ucr_tracker (in_table_name VARCHAR2)
    AS
        --------------------------------------------------------------------------------------------------------------------
        -- archive_active_ucr_tracker input: name of tracker table to be archived.
        --The temp table , and target archive table are hardcoded (could have been params but didn't code it that way).
        --This procedure is the traffic cop to coordinate the archive prccess.
        --task include:
        --1.Sanity check source table (urc_2?) and tmp table.
        --2.get the list of partitions to  archive, for each:
        --3.perform partation swap from source to temp table,
        --4.checks if the archive table has partition empty.
        --5.swaps from temp to archive table in archive schema
        --6.Checks if the partition in the source after swap is empty in source schema.
        --7.If empty then drop the partition from the source.
        --
        -- Because we do not have an account which can query dba_tab_partitions as stored package
        -- we are forced to use "user_tab_partitions" which means this package will identically reside in
        -- both source and target schemas with privs for each to call the other.  This will let schema "a" operate on  partitions within "b".
        --------------------------------------------------------------------------------------------------------------------


        c_table_name                  		 VARCHAR2 (100) := 'TRACKER'; --c_table is the table where the archive data resides and is given hard coded
        v_active_schema               	 VARCHAR2 (100);
        c_exchange_tbl_owner            	VARCHAR2 (100) := USER;
        c_exchange_table_name           	VARCHAR2 (100) := 'TRACKER_PART_EXCHANGE_TMP';
        v_rec                          	 	user_tab_partitions%ROWTYPE;
        v_partition_refcur           	   	SYS_REFCURSOR;
        v_table_temp                  	  	VARCHAR2 (32000);
        v_table_empty                  		NUMBER := 0;
        v_count_partition         	     	 NUMBER := 0;
        v_sql                        		   	VARCHAR2 (32000);
        v_date_of_remote_partition      	DATE;
        v_local_partition_name_for_dt   VARCHAR2 (100);
        v_ok_to_proceed                 	 Number:=1;
	
    BEGIN
        DBMS_OUTPUT.enable (1000000);
        -- sanity check  for active schema(1.FIRST OF ALL it checks if the our source schema is there or not in the database( UCR_2))
        BEGIN
            SELECT ACTIVE_NODE
            INTO v_active_schema
            FROM active_application_node_v
            WHERE app_user = 'GM_CS_UCR_ACTIVE';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error (
                    -20001,
                    SQLERRM || ' Could not lookup active UCR schema from view [active_application_node_v]');
                DBMS_OUTPUT.put_line ('Error checking');
        END;


        EXECUTE IMMEDIATE 'BEGIN ' || v_active_schema || '.partition_util_pkg.RETURN_PARTITION_LIST(:1,:2); END;'
            USING IN in_table_name, IN OUT v_partition_refcur;

        LOOP
            FETCH v_partition_refcur INTO   v_rec;

            EXIT WHEN v_partition_refcur%NOTFOUND;

            -- 3  CALL REMOTE PACKAGE TO PERFORM SWAP
            select count(*) into v_ok_to_proceed from user_tables where table_name = c_exchange_table_name ;
            if (v_ok_to_proceed !=1) then
            raise_application_error(-20014,'Error: Exchange table ['|| c_exchange_table_name||'] does not exist');
            end if;
            
          select count(*) into v_ok_to_proceed from user_tables where table_name = c_table_name ;
            if (v_ok_to_proceed !=1) then
            raise_application_error(-20015,'Error: Target table ['|| c_table_name||'] does not exist');
            end if;
            ----SANITY check to find if  the temp table is empty before the swap from source to temp  begins.
            EXECUTE IMMEDIATE 'SELECT COUNT (*) FROM ' || c_exchange_table_name INTO v_table_empty;

            DBMS_OUTPUT.put_line ('Data in temp table before swap :' || v_table_empty);

           IF (v_table_empty != 0) THEN
              raise_application_error (
                -20012,
                 'ERROR: Exchange table is not empty ['|| c_exchange_table_name || ']');
          END IF;

            --Swaps the partitions by running the package in source schema. After swap THe elligible partitions data will come up in the local temp schema
            --calls the source schema  package to swap the data.
            DBMS_OUTPUT.put_line ('Swap of partition occurs between UCR_2 tracker table and Local TMP table');
            v_sql :=
                   v_active_schema
                || '.partition_util_pkg.Swap_partition_w_exch_tbl('''
                || in_table_name
                || ''','''
                || v_rec.partition_name
                || ''','''
                || c_exchange_tbl_owner
                || ''','''
                || c_exchange_table_name
                || ''')';


            EXECUTE IMMEDIATE ' begin ' || v_sql || '; end;';

            DBMS_OUTPUT.put_line ('Swap success for current partition ');
            DBMS_OUTPUT.put_line (' Get the date for this partition  ');

                      

            -- Display the partition name in local table to swap with the tracker table in archive schema.
            v_sql :=
                   'select '
                || v_active_schema
                || '.partition_util_pkg.get_dt_for_partition_name('''
                || in_table_name
                || ''','''
                || v_rec.partition_name
                || ''') from dual';

            DBMS_OUTPUT.put_line (v_sql);

            EXECUTE IMMEDIATE v_sql INTO v_date_of_remote_partition;

            DBMS_OUTPUT.put_line (v_date_of_remote_partition);

            v_sql :=
                   'SELECT
                partition_util_pkg.get_partition_name_for_dt('''
                || c_table_name
                || ''','''
                || v_date_of_remote_partition
                || ''') FROM dual';

            -- dbms_output.put_line(v_sql);
            EXECUTE IMMEDIATE v_sql INTO v_local_partition_name_for_dt;

            DBMS_OUTPUT.put_line ('***********************************************');

            --check the output of this above v_sql
            -- STEP 2  DO OUR "FAKE" INSERT INTO LOCAL TRACKER TABLE  SO WE HAVE A NEW PARTITION FOR THIS DATE
            -- use fake insert with the date given by get_dt_for_partition_name function to create a partition for the same date range.

            DBMS_OUTPUT.put_line (' In Local Tracker table insert the date obtained and rollback ');
            v_sql :=
                   'INSERT INTO '
                || c_table_name
                || ' (  ACTION_ID  ,ACTION  , TRACKER_TIMESTAMP) SELECT -1,-1,to_date('''
                || v_date_of_remote_partition
                || ''')  FROM DUAL';
            DBMS_OUTPUT.put_line ('SELECT -1,-1,' || v_date_of_remote_partition || '  FROM DUAL');
            DBMS_OUTPUT.put_line (v_sql);

            EXECUTE IMMEDIATE v_sql;

            DBMS_OUTPUT.put_line ('Rollback Here');
            ROLLBACK;

            --get the name of the partitions created above in the archive schema, this should be empty partition
            v_sql :=
                   'SELECT partition_util_pkg.get_partition_name_for_dt ('''
                || c_table_name
                || ''',to_date('''
                || v_date_of_remote_partition
                || '''))  FROM DUAL';
            DBMS_OUTPUT.put_line (v_sql);

            EXECUTE IMMEDIATE v_sql INTO v_local_partition_name_for_dt;

            DBMS_OUTPUT.put_line (v_local_partition_name_for_dt);

            --check if the partition is empty before swap.
            v_sql := ' select count(*) from ' || c_table_name || ' partition(' || v_local_partition_name_for_dt || ')';
            DBMS_OUTPUT.put_line (v_sql);

            EXECUTE IMMEDIATE v_sql INTO v_count_partition;

            DBMS_OUTPUT.put_line (
                   'Number of Records in the target partition tracker table before swap to check if the partition is empty or not:'
                || v_count_partition);

            IF (v_count_partition != 0) THEN
                raise_application_error (-20022, 'ERROR: Partition in archive schema is not empty ['|| c_table_name || ' partition(' || v_local_partition_name_for_dt || ')]');
            END IF;

            -- STEP 3  CALL local PACKAGE TO PERFORM SWAP   (THIS WILL PUT THE 'TMP TABLE INTO OUR LOCAL TRACKER TABLE.

            --  v_sql:= 'partition_util_pkg.Swap_partition_w_exch_tbl('||c_table_name||','|| V_LOCAL_PARTITION_NAME_FOR_DT||','||c_exchange_tbl_owner||','||c_exchange_table_name||')';
            --    dbms_output.put_line(v_sql) ;

            v_sql :=
                   'partition_util_pkg.Swap_partition_w_exch_tbl('''
                || c_table_name
                || ''','''
                || v_local_partition_name_for_dt
                || ''','''
                || c_exchange_tbl_owner
                || ''','''
                || c_exchange_table_name
                || ''')';

            DBMS_OUTPUT.put_line ('Swap between Temp and Archive');


            EXECUTE IMMEDIATE ' begin ' || v_sql || '; end;';

            DBMS_OUTPUT.put_line ('Swap success for current partition ');
            DBMS_OUTPUT.put_line ('In Active Node   ');
            DBMS_OUTPUT.put_line (
                '******************Drop the empty partition in UCR_2 schema*****************************');

            --Drop empty partition from the source schema after the swap is successful
            --drop_empty_partition
            DBMS_OUTPUT.put_line ('table name ' || in_table_name || 'and partition ' || v_rec.partition_name);
            v_sql :=
                   v_active_schema
                || '.partition_util_pkg.drop_empty_partition('''
                || in_table_name
                || ''','''
                || v_rec.partition_name
                || ''')';

            DBMS_OUTPUT.put_line (v_sql);
            EXECUTE IMMEDIATE ' begin ' || v_sql || '; end;';
            DBMS_OUTPUT.put_line ('***********************************************');
        END LOOP;

        CLOSE v_partition_refcur;
    END   archive_active_ucr_tracker;





    FUNCTION get_dt_for_partition_name (in_table_name VARCHAR2, in_partition_name VARCHAR2)
        RETURN DATE
    IS
        --------------------------------------------------------------------------------------------------------------------
        -- get_dt_for_partition_name assumes input table is interval partitioned,receive table_name and a partition_name
        -- obtain the "high_value",convert to time subtract 1 second and that is the max "date" for that partition.
        -- the initial parition might span many dates and this is the max date for that partition for all others
        -- for all other partitions this will be the 23:59:59 hour for that day.
        --------------------------------------------------------------------------------------------------------------------
        out_dt   DATE := '';
    BEGIN
        WITH partition_xml
             AS (SELECT DBMS_XMLGEN.getxmltype (
                               'select table_name,partition_name,high_value from user_tab_partitions where PARTITION_NAME = '''
                            || in_partition_name
                            || '''and table_name = '''
                            || in_table_name
                            || '''')
                            AS x
                 FROM DUAL),
             partition_list
             AS (SELECT EXTRACTVALUE (rws.object_value, '/ROW/PARTITION_NAME') partition_name,
                        TO_DATE (
                            REPLACE (REPLACE (EXTRACTVALUE (rws.object_value, '/ROW/HIGH_VALUE'), 'TIMESTAMP'' ', ''),
                                     ' 00:00:00''',
                                     ''
                                    ),
                            'yyyy-mm-dd')
                            high_value
                 FROM partition_xml x, TABLE (XMLSEQUENCE (EXTRACT (x.x, '/ROWSET/ROW'))) rws)
        SELECT high_value - (1 / (24 * 60 * 60))
        INTO out_dt
        FROM partition_list
        WHERE partition_name = in_partition_name;

        RETURN (out_dt);
    END   get_dt_for_partition_name;
    
   
END partition_util_pkg;
/
