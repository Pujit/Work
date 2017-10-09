create or replace PACKAGE partition_util_pkg
IS
    --------------------------------------------------------------------------------------------------------------------------
    -- ver# date        Author/description
    -- ---- ----------- -------------------------------------------------------------------------------------------------------
    -- 1.0  2017_05_31  Pujit Koirala/Paul Healy - Initial version 440.227.9043
    --                  GM-1226 Story_3_of_N: pl/sql block to move partitions of tracker data from the live "tracker" to archive
    --
    ---------------------------------------------------------------------------------------------------------------------------



    --------------------------------------------------------------------------------------------------------------------
    -- drop_empty_partition drops the partitions for the given table if present.Before it drops it checks if the partition is empty or not.
    --If partition is not empty it raise error
    --If the table doesn't exist then raise error,if partition doesn't exits then raise error
    --------------------------------------------------------------------------------------------------------------------
    PROCEDURE drop_empty_partition (in_table_name VARCHAR2, in_partition_name VARCHAR2);



    --------------------------------------------------------------------------------------------------------------------
    -- return_partition_list  will list all the partitions present for the given table within the valid date range that can be archived based on our retention policy.
    --
    --------------------------------------------------------------------------------------------------------------------
    PROCEDURE RETURN_PARTITION_LIST (in_tablename VARCHAR, C_QRY IN OUT SYS_REFCURSOR);



    --------------------------------------------------------------------------------------------------------------------
    -- swap_partition_w_exch_tbl will swap a partition and a stand alone exchange  tables.
    -- to move single partition from an existing partitioned table into a different partitioned table
    -- you would call this procedure twice, once to move the partition from the source into the standalone
    -- and then  again to move from the standalone into the target partitioned table.
    --------------------------------------------------------------------------------------------------------------------
    PROCEDURE Swap_partition_w_exch_tbl (IN_TABLE_NAME             VARCHAR2,
                                         in_partition_name         VARCHAR2,
                                         in_exchange_tbl_owner     VARCHAR2,
                                         in_exchange_table_name    VARCHAR2
                                        );



    --------------------------------------------------------------------------------------------------------------------
    -- get_partition_name_for_dt assumes input table is interval partitioned, receive table_name and a date
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
    FUNCTION get_partition_name_for_dt (in_table_name VARCHAR2, in_dt DATE)
        RETURN VARCHAR2;



    --------------------------------------------------------------------------------------------------------------------
    -- get_dt_for_partition_name assumes input table is interval partitioned, receive table_name and a partition_name
    -- obtain the "high_value", convert to time subtract 1 second and that is the max "date" for that partition.
    -- the initial parition might span many dates and this is the max date for that partition for all others
    -- for all other partitions this will be the 23:59:59 hour for that day.
    --------------------------------------------------------------------------------------------------------------------
    FUNCTION get_dt_for_partition_name (in_table_name VARCHAR2, in_partition_name VARCHAR2)
        RETURN DATE;



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
    PROCEDURE ARCHIVE_ACTIVE_UCR_TRACKER (IN_TABLE_NAME VARCHAR2);
    
END partition_util_pkg;
