USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[update_move_postprocessing_DrvAVL]    Script Date: 1/20/2025 9:24:49 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

-- MB Changed 10/28/2024 add code to deal with 2051 datetime
ALTER PROCEDURE [dbo].[update_move_postprocessing_DrvAVL] (@mov INT)
AS
BEGIN
    -- Temporary table to store relevant orders
    CREATE TABLE #order (
        ord_status VARCHAR(6),
        ord_hdrnumber INT,
        lgh_driver VARCHAR(8),
        mov_number INT
    )

    -- Insert data into temporary table based on criteria
    INSERT INTO #order (ord_status, ord_hdrnumber, lgh_driver, mov_number)
    SELECT lgh_outstatus, ord_hdrnumber, lgh_driver1, mov_number
    FROM legheader
    WHERE lgh_outstatus NOT IN ('CAN','MST','ICO')
      AND lgh_enddate > GETDATE() - 21 
      AND mov_number = @mov

    -- Check if any records exist in the temporary table
    IF EXISTS (SELECT 1 FROM #order)
    BEGIN
        -- Update mpp_lastmobilecomm to NULL for manpowerprofile if conditions are met
        UPDATE [TMW_Live].dbo.manpowerprofile
        SET mpp_lastmobilecomm = NULL
        WHERE mpp_avl_status <> 'OUT' 
          AND mpp_lastmobilecomm IS NOT NULL
          AND mpp_lastmobilecomm < mpp_avl_date;

        -- Update mpp_avl_date to mpp_lastmobilecomm if conditions are met
        UPDATE [TMW_Live].dbo.manpowerprofile
        SET mpp_avl_date = mpp_lastmobilecomm
        WHERE mpp_avl_status <> 'OUT' 
          AND mpp_lastmobilecomm IS NOT NULL
          AND mpp_lastmobilecomm > mpp_avl_date;

        -- Additional update logic for mpp_avl_date based on expiration and legheader data
        UPDATE m
        SET m.mpp_avl_date = (
            SELECT TOP 1
                CASE 
                    WHEN e.exp_expirationdate <= GETDATE() 
                         AND e.exp_completed = 'N' 
                         AND e.exp_code IN ('VAC','HOME','OO','OJT','LOA','SAF','SIC') 
                    THEN CONVERT(VARCHAR, e.exp_expirationdate, 120)
                    ELSE 
                        CASE 
                            WHEN l.lgh_enddate > m.mpp_avl_date 
                            THEN CONVERT(VARCHAR, l.lgh_enddate, 120) 
                            ELSE m.mpp_avl_date 
                        END
                END AS result_date
            FROM expiration e
            INNER JOIN legheader l ON l.lgh_driver1 = e.exp_id
            WHERE e.exp_id = m.mpp_id
            ORDER BY l.lgh_enddate DESC
        )
        FROM manpowerprofile m
        JOIN legheader l ON l.lgh_driver1 = m.mpp_id
        WHERE m.mpp_status <> 'OUT' 
          AND l.mov_number = @mov;


				declare @mpp_avl_date datetime 
				declare @mpp_id varchar(50)

                                   
                    select @mpp_avl_date =  max(  CASE 
                    WHEN e.exp_expirationdate <= GETDATE() 
                         AND e.exp_completed = 'N' 
                         AND e.exp_code IN ('VAC','HOME','OO','OJT','LOA','SAF','SIC') 
                    THEN CONVERT(VARCHAR, isnull(e.exp_expirationdate,l.lgh_enddate), 120)
                    ELSE 
                                                                                  
                        CASE 
                            WHEN (l.lgh_enddate < m.mpp_avl_date) --or (m.mpp_avl_date >= '12/31/2049')
                            THEN CONVERT(VARCHAR, l.lgh_enddate, 120) 
                            WHEN (m.mpp_avl_date >= '12/31/2049')
                            THEN CONVERT(VARCHAR, l.lgh_enddate, 120) 
                            ELSE m.mpp_avl_date 
                        END
                END ) 
                        , @mpp_id = mpp_id
            FROM legheader l  
            left outer JOIN expiration e
            ON l.lgh_driver1 = e.exp_id
        inner join  manpowerprofile m
        ON l.lgh_driver1 = m.mpp_id
        WHERE m.mpp_status <> 'OUT'
         and        l.mov_number = @mov
         group by mpp_id

		update m
		set m.mpp_avl_date = @mpp_avl_date
		from manpowerprofile m
		where m.mpp_id = @mpp_id






    END
END
GO


