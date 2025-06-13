USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[update_move_processing_sp]    Script Date: 1/20/2025 9:37:42 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[update_move_processing_sp](@mov             INTEGER,
                                              @assetassignmnet CHAR(1))
AS

/**************************************************************************************************************************************************************************
 **
 ** Parameters:
 **   Input:
 **     @mov              INTEGER
 **       - mov_number to process
 **     @assetassignment  CHAR(1)
 **       - skips running update_assetassignment stored procedure when not 'Y'
 **
 ** GeneralInfo Setting:
 **   HourlyPaywithBonus (Default=0)
 **     - when String1 = '1' calculated planned hours for leg based on events(from eventcodetable) and drive times(from mileagetable)
 **
 ** DriverTractorTypesFixedOnCMP (Default=N for String1 and String2)
 **   - when String1 = 'Y' - do not change mpp_type fields on leg once complete unless driver1 or driver2 changes
 **   - when String1 = 'N' - mpp_type fields are updated to match manpowerprofile for driver1 and driver2 all the time
 **   - when String2 = 'Y' - do not change trc_type fields on leg once complete unless tractor changes
 **   - when String2 = 'N' - trc_type fields are updated to match tractorprofile for tractor all the time
 **
 ** PrevSegmentStatus (Default=N)
 **   - when String1 = 'Y' populate the lgh_prev_seg_status and lgh_prev_seg_status_last_updated fields with info from tractor's previous leg
 **
 ** UpdateMoveOrdFromLeg (Default=N)
 **   - when String1 = 'Y' Populate legs ord_hdrnumber from with MAX(ord_hdrnumber) from stops on leg (if this would be 0 then use MAX(ord_hdrnumber from stops on move)
 **
 ** UpdateMovePostProcessing (Default=N)
 **   - when String1 = 'Y' executes the update_move_postprocessing stored procedure
 **
 ** DisplayPendingOrders (Default=N)
 **   - when String1 = 'Y' uses String2 as list of Order Statuses to set lgh_outstatus
 **
 ** HazMatMileageLookups (Default=N)
 **   - when String1 = 'Y' populates the lgh_hzd_cmd_class field with appropriate hazardous cmd_class
 **
 ** CompleteOnDeparture (Default=N)
 **   - when String1 = 'Y' leg is only considered complete when last stops departure status = DNE (stp_departure_status)
 **   - when String1 <> 'Y' leg is considered complete when last stops status = DNE (stp_status)
 **
 ** TrackBranch (Default=N)
 **   - when String1 = 'Y' will update ord_broker on orderheader to match lgh_booked_revtype1
 **   - String2 is the default booked revtype1 value (Default=UNKNOWN)
 **
 ** SoftPTATime (Default=N)
 **   - when String1 = 'Y' calls the LegPTAUpdate_sp stored procedure
 **
 ** AllowMasterAssignments (Default=N)
 **   - when String1 = 'Y' leave assets on events on legs that have stops with stp_status = NON
 **   - when String1 <> 'N' removes assets on events on legs that have stops with stp_status = NON
 **   
 ** CheckPermitRequirementsOnSave (Default=N)
 **   - when String1 = 'Y' calls the reset_permitrequirements_sp stored procedure
 **
 ** FixOrderSequences (Default=N)
 **   - when String1 = 'Y' calls the Fix_Order_Sequences stored procedure
 **
 ** EnhPltTrkng (Default=N)
 **   - when String1 = 'Y' calls the generate_pallet_tracking_sp stored procdure
 **
 ** CDI (Default=N)
 **   - when String1 = 'Y' calls the fuel_transaction_queue stored procedure to populate interactive fuel queue
 **
 ** TCHRealTime (Default=N)
 **   - when String1 = 'Y' calls the tch_transaction_queue stored procedure to populate the tch interactive queue
 **
 ** OrderCustomDate (Default=N)
 **   - when String1 = 'Y' populates ord_customdate on the orderheader table
 **   - String2 (Default=PUPDEP)
 **     - when PUPARR then custom date comes from first PUP that has been arrived 
 **     - when PUPDEP then custom date comes from the first PUP that has been departed
 **     - when DRPARR then custom date comes from first DRP that has been arrived 
 **     - when DRPDEP then custom date comes from the first DRP that has been departed
 **   - String3 (Default=CURRENT)
 **     - when CURRENT uses the GETDATE for custom date
 **     - otherwise uses either arrival or departure date from stop depending on String2
 **
 ** ProcessOutbound204 (Default=N)
 **   - String1 needs to be set to 'Y' for Outbound204RailBilling and ValidateOutbound204 to be checked
 **
 ** Outbound204RailBilling (Default=N)
 **   - when String1 = 'Y' sets the lgh_raildispatchstatus for legs that have DLT & HLT events where companies are rail ramps
 **
 ** ValidateOutbound204 (Default=N)
 **   - when String1 = 'Y' sets the lgh_204validate based on carriers car_204validate field
 **     - car_204validate = 0 set field to 1
 **     - car_204validate = 1
 **       - set field to 0 on new legs
 **       - set field to 0 if carrier changed
 **       - leave field alone if carrier didn't change
 ** 
 ** TractorDriverForPlanned (Default=N)
 **   - when String1 = 'Y' need to have both a tractor and driver for leg to be considered planned
 **   - when String2 = 'Y' having just a carrier assigned will allow a leg to be considered planned; otherwise just a carrier is not sufficent with string1 set to 'Y'.
 **
 ** Revison History:
 **   INT-106022 - RJE 03/31/2017 - Created new procedure to consolidate update_move and update_move light
 **Date        Name             Label/PTS   Description
  -----------  ---------------  ----------  ------------------------------------------------------------------------
  07/09/2018   David Wilks	  PB-200186   send outbound 204 cancel when leg with 204 carrier is being deleted
  09/07/2018   Cory Sellers   PB-200255   Updating order header number for legs for that have manifests (needed for 
										  turnpike doubles interoperability rewrite (see NSUITE-204402).
  05/28/2019   David Wilks	  PB-200636   legheaders were getting created for PND orders. (caused by PB-200186)
  10/19/2023   Matt Roberts   TTESUITE-200694 Added a call to a new stored proc BypassLTLMove to bypass running proc for LTL moves.
********************************************************************************************************************/
	 DECLARE @bypass INTEGER;
	 EXEC BypassLTLMove @mov, @bypass OUT
	 IF @bypass = 1
	 BEGIN
		RETURN;
	 END
	 
     SET NOCOUNT ON;
     DECLARE @HourlyPaywithBonus VARCHAR(60), @FixMppTypesOnCmp CHAR(1), @FixTrcTypesOnCmp CHAR(1), @PreviousSegmentStatus CHAR(1), @UseOrdFromLeg CHAR(1), @UpdateMovePostProcessing CHAR(1), @DisplayPendingOrders CHAR(1), @PendingStatuses VARCHAR(60), @PendingStatusCodes TMWTABLE_CHAR6, @HazMatMileageLookups CHAR(1), @LghActiveUntilDepCompNBC CHAR(1), @CompleteOnDeparture CHAR(1), @TrackBranch CHAR(1), @DefaultLghBookedRevType1 VARCHAR(6), @OEAllowOrdBrokerUpdate CHAR(1), @SoftPta CHAR(1), @AllowMasterAssignments CHAR(1), @CheckPermitRequirementsOnSave CHAR(1), @FixOrderSequences CHAR(1), @EnhPltTrkng CHAR(1), @FuelInterface CHAR(1), @TchRealTimeStatus CHAR(1), @TchRealTimeTractor CHAR(1), @TchRealTimeTrailer CHAR(1), @TchRealTimeTrip CHAR(1), @OrderCustomDate CHAR(1), @CustomDateOrigin VARCHAR(60), @CustomDateSource VARCHAR(60), @ProcessOutbound204 CHAR(1), @Outbound204RailBilling CHAR(1), @ValidateOutbound204 CHAR(1), @TractorDriverForPlanned CHAR(1), @CarrierPlanned CHAR(1), @tmwuser VARCHAR(255), @inbond TINYINT, @inboundsequence INTEGER, @minTractor VARCHAR(8), @minDriver VARCHAR(8), @minTrailer VARCHAR(13), @lgh INTEGER, @car_id VARCHAR(8), @prevlgh INTEGER, @tractor VARCHAR(8), @cmd_code VARCHAR(8), @stp_description VARCHAR(60), @legs INTEGER, @updatemoveprocessingstops UPDATEMOVEPROCESSINGSTOPS, @updatemoveprocessinglegs UPDATEMOVEPROCESSINGLEGS;
     DECLARE @Drivers TABLE(mpp_id VARCHAR(8) NOT NULL);
     DECLARE @Tractors TABLE(trc_number VARCHAR(8) NOT NULL);
     DECLARE @Trailers TABLE(trl_id VARCHAR(13) NOT NULL);
     DECLARE @lghTable TABLE
     (crud_type                        CHAR(1) NOT NULL,
      legsequence                      INTEGER NULL,
      legcount                         INTEGER NULL,
      lgh_number                       INTEGER NOT NULL
                                               PRIMARY KEY,
      ord_hdrnumber                    INTEGER NULL,
      mov_number                       INTEGER NULL,
      lgh_priority                     VARCHAR(6) NULL,
      lgh_schdtearliest                DATETIME NULL,
      lgh_schdtlatest                  DATETIME NULL,
      cmd_code                         VARCHAR(8) NULL,
      fgt_description                  VARCHAR(60) NULL,
      lgh_outstatus                    VARCHAR(6) NULL,
      lgh_204status                    VARCHAR(6) NULL,
      lgh_instatus                     VARCHAR(6) NULL,
      lgh_fueltaxstatus                VARCHAR(6) NULL,
      lgh_active                       CHAR(1) NULL,
      lgh_class1                       VARCHAR(6) NULL,
      lgh_class2                       VARCHAR(6) NULL,
      lgh_class3                       VARCHAR(6) NULL,
      lgh_class4                       VARCHAR(6) NULL,
      lgh_type1                        VARCHAR(6) NULL,
      lgh_type2                        VARCHAR(6) NULL,
      lgh_type3                        VARCHAR(6) NULL,
      lgh_type4                        VARCHAR(6) NULL,
      lgh_type5                        VARCHAR(6) NULL,
      cmp_id_start                     VARCHAR(8) NULL,
      lgh_startcty_nmstct              VARCHAR(25) NULL,
      lgh_startcity                    INTEGER NULL,
      lgh_originzip                    VARCHAR(10) NULL,
      lgh_startlat                     INTEGER NULL,
      lgh_startlong                    INTEGER NULL,
      stp_number_start                 INTEGER NULL,
      lgh_startstate                   VARCHAR(6) NULL,
      lgh_startdate                    DATETIME NULL,
      lgh_startregion1                 VARCHAR(6) NULL,
      lgh_startregion2                 VARCHAR(6) NULL,
      lgh_startregion3                 VARCHAR(6) NULL,
      lgh_startregion4                 VARCHAR(6) NULL,
      cmp_id_end                       VARCHAR(8) NULL,
      lgh_endcty_nmstct                VARCHAR(25) NULL,
      lgh_endcity                      INTEGER NULL,
      lgh_destzip                      VARCHAR(10) NULL,
      lgh_endlat                       INTEGER NULL,
      lgh_endlong                      INTEGER NULL,
      stp_number_end                   INTEGER NULL,
      lgh_endstate                     VARCHAR(6) NULL,
      lgh_enddate                      DATETIME NULL,
      lgh_enddate_arrival              DATETIME NULL,
      lgh_endregion1                   VARCHAR(6) NULL,
      lgh_endregion2                   VARCHAR(6) NULL,
      lgh_endregion3                   VARCHAR(6) NULL,
      lgh_endregion4                   VARCHAR(6) NULL,
      lgh_driver1                      VARCHAR(8) NULL,
      lgh_driver2                      VARCHAR(8) NULL,
      mpp_teamleader                   VARCHAR(6) NULL,
      mpp_fleet                        VARCHAR(6) NULL,
      mpp_division                     VARCHAR(6) NULL,
      mpp_domicile                     VARCHAR(6) NULL,
      mpp_company                      VARCHAR(6) NULL,
      mpp_terminal                     VARCHAR(6) NULL,
      mpp_type1                        VARCHAR(6) NULL,
      mpp_type2                        VARCHAR(6) NULL,
      mpp_type3                        VARCHAR(6) NULL,
      mpp_type4                        VARCHAR(6) NULL,
      mpp2_type1                       VARCHAR(6) NULL,
      mpp2_type2                       VARCHAR(6) NULL,
      mpp2_type3                       VARCHAR(6) NULL,
      mpp2_type4                       VARCHAR(6) NULL,
      lgh_tractor                      VARCHAR(8) NULL,
      trc_company                      VARCHAR(6) NULL,
      trc_division                     VARCHAR(6) NULL,
      trc_teamleader                   VARCHAR(6) NULL,
      trc_fleet                        VARCHAR(6) NULL,
      trc_terminal                     VARCHAR(6) NULL,
      trc_type1                        VARCHAR(6) NULL,
      trc_type2                        VARCHAR(6) NULL,
      trc_type3                        VARCHAR(6) NULL,
      trc_type4                        VARCHAR(6) NULL,
      lgh_primary_trailer              VARCHAR(13) NULL,
      lgh_primary_pup                  VARCHAR(13) NULL,
      lgh_trailer3                     VARCHAR(13) NULL,
      lgh_trailer4                     VARCHAR(13) NULL,
      lgh_chassis                      VARCHAR(13) NULL,
      lgh_chassis2                     VARCHAR(13) NULL,
      lgh_dolly                        VARCHAR(13) NULL,
      lgh_dolly2                       VARCHAR(13) NULL,
      trl_company                      VARCHAR(6) NULL,
      trl_fleet                        VARCHAR(6) NULL,
      trl_division                     VARCHAR(6) NULL,
      trl_terminal                     VARCHAR(6) NULL,
      trl_type1                        VARCHAR(6) NULL,
      trl_type2                        VARCHAR(6) NULL,
      trl_type3                        VARCHAR(6) NULL,
      trl_type4                        VARCHAR(6) NULL,
      lgh_carrier                      VARCHAR(8) NULL,
      lgh_createdby                    VARCHAR(128) NULL,
      lgh_createdon                    DATETIME NULL,
      lgh_createapp                    VARCHAR(128) NULL,
      lgh_updatedby                    VARCHAR(128) NULL,
      lgh_updatedon                    DATETIME NULL,
      lgh_updateapp                    VARCHAR(128) NULL,
      lgh_odometerstart                INTEGER NULL,
      lgh_odometerend                  INTEGER NULL,
      cmp_id_rstart                    VARCHAR(8) NULL,
      lgh_rstartcty_nmstct             VARCHAR(25) NULL,
      lgh_rstartcity                   INTEGER NULL,
      lgh_rstartlat                    INTEGER NULL,
      lgh_rstartlong                   INTEGER NULL,
      stp_number_rstart                INTEGER NULL,
      lgh_rstartstate                  VARCHAR(6) NULL,
      lgh_rstartdate                   DATETIME NULL,
      lgh_rstartregion1                VARCHAR(6) NULL,
      lgh_rstartregion2                VARCHAR(6) NULL,
      lgh_rstartregion3                VARCHAR(6) NULL,
      lgh_rstartregion4                VARCHAR(6) NULL,
      cmp_id_rend                      VARCHAR(8) NULL,
      lgh_rendcty_nmstct               VARCHAR(25) NULL,
      lgh_rendcity                     INTEGER NULL,
      lgh_rendlat                      INTEGER NULL,
      lgh_rendlong                     INTEGER NULL,
      stp_number_rend                  INTEGER NULL,
      lgh_rendstate                    VARCHAR(6) NULL,
      lgh_renddate                     DATETIME NULL,
      lgh_rendregion1                  VARCHAR(6) NULL,
      lgh_rendregion2                  VARCHAR(6) NULL,
      lgh_rendregion3                  VARCHAR(6) NULL,
      lgh_rendregion4                  VARCHAR(6) NULL,
      lgh_miles                        INTEGER NULL,
      lgh_reftype                      VARCHAR(6) NULL,
      lgh_refnum                       VARCHAR(30) NULL,
      lgh_linehaul                     FLOAT NULL,
      lgh_ord_charge                   FLOAT NULL,
      lgh_act_weight                   FLOAT NULL,
      lgh_est_weight                   FLOAT NULL,
      lgh_tot_weight                   FLOAT NULL,
      lgh_route                        VARCHAR(15) NULL,
      lgh_direct_route_status1         VARCHAR(6) NULL,
      lgh_booked_revtype1              VARCHAR(12) NULL,
      lgh_204validate                  INTEGER NULL,
      lgh_split_flag                   CHAR(1) NULL,
      lgh_hzd_cmd_class                VARCHAR(8) NULL,
      lgh_prev_seg_status              VARCHAR(6) NULL,
      lgh_prev_seg_status_last_updated DATETIME NULL,
      lgh_plannedhours                 DECIMAL(6, 2) NULL,
      lgh_raildispatchstatus           VARCHAR(6) NULL
     );
     DECLARE @stpTable TABLE
     (stp_number                INTEGER NOT NULL
                                        PRIMARY KEY,
      mov_number                INTEGER NULL,
      lgh_number                INTEGER NULL,
      ord_hdrnumber             INTEGER NULL,
      stp_mfh_sequence          INTEGER NULL,
      stp_arrivaldate           DATETIME NULL,
      stp_departuredate         DATETIME NULL,
      stp_status                VARCHAR(6) NULL,
      stp_departure_status      VARCHAR(6) NULL,
      stp_lgh_mileage           INTEGER NULL,
      stp_event                 VARCHAR(6) NULL,
      stp_type                  VARCHAR(6) NULL,
      stp_loadstatus            VARCHAR(3) NULL,
      cmd_code                  VARCHAR(8) NULL,
      stp_description           VARCHAR(60) NULL,
      cmp_id                    VARCHAR(8) NULL,
      stp_city                  INTEGER NULL,
      stp_zipcode               VARCHAR(10) NULL,
      stp_schdtearliest         DATETIME NULL,
      stp_schdtlatest           DATETIME NULL,
      stp_transfer_type         VARCHAR(6) NULL,
      evt_driver1               VARCHAR(8) NULL,
      evt_driver2               VARCHAR(8) NULL,
      evt_tractor               VARCHAR(8) NULL,
      evt_trailer1              VARCHAR(13) NULL,
      evt_trailer2              VARCHAR(13) NULL,
      evt_trailer3              VARCHAR(13) NULL,
      evt_trailer4              VARCHAR(13) NULL,
      evt_dolly                 VARCHAR(13) NULL,
      evt_dolly2                VARCHAR(13) NULL,
      evt_chassis               VARCHAR(13) NULL,
      evt_chassis2              VARCHAR(13) NULL,
      evt_carrier               VARCHAR(8) NULL,
      evt_hubmiles              INTEGER NULL,
      stp_lgh_mileage_mtid      INTEGER NULL,
      stp_ico_stp_number_parent INTEGER NULL
     );
     DECLARE @evtTable TABLE
     (evt_number    INTEGER NOT NULL
                            PRIMARY KEY,
      stp_number    INTEGER NOT NULL,
      evt_sequence  INTEGER NOT NULL,
      ord_hdrnumber INTEGER NOT NULL
     );
     SELECT @HourlyPaywithBonus = CASE
                                      WHEN gi_name = 'HourlyPaywithBonus'
                                      THEN COALESCE(gi_string1, '0')
                                      ELSE @HourlyPaywithBonus
                                  END,
            @FixMppTypesOnCmp = CASE
                                    WHEN gi_name = 'DriverTractorTypesFixedOnCMP'
                                    THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                    ELSE @FixMppTypesOnCmp
                                END,
            @FixTrcTypesOnCmp = CASE
                                    WHEN gi_name = 'DriverTractorTypesFixedOnCMP'
                                    THEN LEFT(COALESCE(gi_string2, 'N'), 1)
                                    ELSE @FixTrcTypesOnCmp
                                END,
            @PreviousSegmentStatus = CASE
                                         WHEN gi_name = 'PrevSegmentStatus'
                                         THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                         ELSE @PreviousSegmentStatus
                                     END,
            @UseOrdFromLeg = CASE
                                 WHEN gi_name = 'UpdateMoveOrdFromLeg'
                                 THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                 ELSE @UseOrdFromLeg
                             END,
            @UpdateMovePostProcessing = CASE
                                            WHEN gi_name = 'UpdateMovePostProcessing'
                                            THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                            ELSE @UpdateMovePostProcessing
                                        END,
            @DisplayPendingOrders = CASE
                                        WHEN gi_name = 'DisplayPendingOrders'
                                        THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                        ELSE @DisplayPendingOrders
                                    END,
            @PendingStatuses = CASE
                                   WHEN gi_name = 'DisplayPendingOrders'
                                   THEN gi_string2
                                   ELSE @PendingStatuses
                               END,
            @HazMatMileageLookups = CASE
                                        WHEN gi_name = 'HazMatMileageLookups'
                                        THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                        ELSE @HazMatMileageLookups
                                    END,
            @LghActiveUntilDepCompNBC = CASE
                                            WHEN gi_name = 'LghActiveUntilDepCompNBC'
                                            THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                            ELSE @LghActiveUntilDepCompNBC
                                        END,
            @CompleteOnDeparture = CASE
                                       WHEN gi_name = 'CompleteOnDeparture'
                                       THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                       ELSE @CompleteOnDeparture
                                   END,
            @TrackBranch = CASE
                               WHEN gi_name = 'TrackBranch'
                               THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                               ELSE @TrackBranch
                           END,
            @DefaultLghBookedRevType1 = CASE
                                            WHEN gi_name = 'TrackBranch'
                                            THEN LEFT(COALESCE(gi_string4, ''), 6)
                                            ELSE @DefaultLghBookedRevType1
                                        END,
            @OEAllowOrdBrokerUpdate = CASE
                                          WHEN gi_name = 'OEAllowOrdBrokerUpdate'
                                          THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                          ELSE @OEAllowOrdBrokerUpdate
                                      END,
            @SoftPta = CASE
                           WHEN gi_name = 'SoftPTATime'
                           THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                           ELSE @SoftPta
                       END,
            @AllowMasterAssignments = CASE
                                          WHEN gi_name = 'AllowMasterAssignments'
                                          THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                          ELSE @AllowMasterAssignments
                                      END,
            @CheckPermitRequirementsOnSave = CASE
                                                 WHEN gi_name = 'CheckPermitRequirementsOnSave'
                                                 THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                                 ELSE @CheckPermitRequirementsOnSave
                                             END,
            @FixOrderSequences = CASE
                                     WHEN gi_name = 'FixOrderSequences'
                                     THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                     ELSE @FixOrderSequences
                                 END,
            @EnhPltTrkng = CASE
                               WHEN gi_name = 'EnhPltTrkng'
                               THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                               ELSE @EnhPltTrkng
                           END,
            @FuelInterface = CASE
                                 WHEN gi_name = 'CDI'
                                 THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                 ELSE @FuelInterface
                             END,
            @TchRealTimeStatus = CASE
                                     WHEN gi_name = 'TCHRealTime'
                                     THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                     ELSE @TchRealTimeStatus
                                 END,
            @TchRealTimeTractor = CASE
                                      WHEN gi_name = 'TCHRealTime'
                                      THEN LEFT(COALESCE(gi_string2, 'N'), 1)
                                      ELSE @TchRealTimeTractor
                                  END,
            @TchRealTimeTrailer = CASE
                                      WHEN gi_name = 'TCHRealTime'
                                      THEN LEFT(COALESCE(gi_string3, 'N'), 1)
                                      ELSE @TchRealTimeTrailer
                                  END,
            @TchRealTimeTrip = CASE
                                   WHEN gi_name = 'TCHRealTime'
                                   THEN LEFT(COALESCE(gi_string4, 'N'), 1)
                                   ELSE @TchRealTimeTrip
                               END,
            @OrderCustomDate = CASE
                                   WHEN gi_name = 'OrderCustomDate'
                                   THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                   ELSE @OrderCustomDate
                               END,
            @CustomDateOrigin = CASE
                                    WHEN gi_name = 'OrderCustomDate'
                                    THEN COALESCE(gi_string2, 'PUPDEP')
                                    ELSE @CustomDateOrigin
                                END,
            @CustomDateSource = CASE
                                    WHEN gi_name = 'OrderCustomDate'
                                    THEN COALESCE(gi_string3, 'CURRENT')
                                    ELSE @CustomDateSource
                                END,
            @ProcessOutbound204 = CASE
                                      WHEN gi_name = 'ProcessOutbound204'
                                      THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                      ELSE @ProcessOutbound204
                                  END,
            @Outbound204RailBilling = CASE
                                          WHEN gi_name = 'Outbound204RailBilling'
                                          THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                          ELSE @Outbound204RailBilling
                                      END,
            @ValidateOutbound204 = CASE
                                       WHEN gi_name = 'ValidateOutbound204'
                                       THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                       ELSE @ValidateOutbound204
                                   END,
            @TractorDriverForPlanned = CASE
                                           WHEN gi_name = 'TractorDriverForPlanned'
                                           THEN LEFT(COALESCE(gi_string1, 'N'), 1)
                                           ELSE @TractorDriverForPlanned
								   END,
            @CarrierPlanned = CASE         
										   WHEN gi_name = 'TractorDriverForPlanned'
                                           THEN LEFT(COALESCE(gi_string2, 'N'), 1)
                                           ELSE @CarrierPlanned										   
                                       END
     FROM generalinfo WITH (NOLOCK)
     WHERE gi_name IN('HourlyPaywithBonus', 'DriverTractorTypesFixedOnCMP', 'PrevSegmentStatus', 'UpdateMoveOrdFromLeg', 'UpdateMovePostProcessing', 'DisplayPendingOrders', 'HazMatMileageLookups', 'LghActiveUntilDepCompNBC', 'CompleteOnDeparture', 'TrackBranch', 'SoftPTATime', 'AllowMasterAssignments', 'CheckPermitRequirementsOnSave', 'FixOrderSequences', 'EnhPltTrkng', 'CDI', 'TCHRealTime', 'OrderCustomDate', 'ProcessOutbound204', 'Outbound204RailBilling', 'ValidateOutbound204', 'TractorDriverForPlanned');
     SELECT @HourlyPaywithBonus = COALESCE(@HourlyPaywithBonus, '0'),
            @FixMppTypesOnCmp = COALESCE(@FixMppTypesOnCmp, 'N'),
            @FixTrcTypesOnCmp = COALESCE(@FixTrcTypesOnCmp, 'N'),
            @PreviousSegmentStatus = COALESCE(@PreviousSegmentStatus, 'N'),
            @UseOrdFromLeg = COALESCE(@UseOrdFromLeg, 'N'),
            @UpdateMovePostProcessing = COALESCE(@UpdateMovePostProcessing, 'N'),
            @DisplayPendingOrders = COALESCE(@DisplayPendingOrders, 'N'),
            @HazMatMileageLookups = COALESCE(@HazMatMileageLookups, 'N'),
            @LghActiveUntilDepCompNBC = COALESCE(@LghActiveUntilDepCompNBC, 'N'),
            @CompleteOnDeparture = COALESCE(@CompleteOnDeparture, 'N'),
            @TrackBranch = COALESCE(@TrackBranch, 'N'),
            @DefaultLghBookedRevType1 = COALESCE(@DefaultLghBookedRevType1, ''),
            @OEAllowOrdBrokerUpdate = COALESCE(@OEAllowOrdBrokerUpdate, 'N'),
            @SoftPta = COALESCE(@SoftPta, 'N'),
            @AllowMasterAssignments = COALESCE(@AllowMasterAssignments, 'N'),
            @CheckPermitRequirementsOnSave = COALESCE(@CheckPermitRequirementsOnSave, 'N'),
            @FixOrderSequences = COALESCE(@FixOrderSequences, 'N'),
            @EnhPltTrkng = COALESCE(@EnhPltTrkng, 'N'),
            @FuelInterface = COALESCE(@FuelInterface, 'N'),
            @TchRealTimeStatus = COALESCE(@TchRealTimeStatus, 'N'),
            @TchRealTimeTractor = COALESCE(@TchRealTimeTractor, 'N'),
            @TchRealTimeTrailer = COALESCE(@TchRealTimeTrailer, 'N'),
            @TchRealTimeTrip = COALESCE(@TchRealTimeTrip, 'N'),
            @OrderCustomDate = COALESCE(@OrderCustomDate, 'N'),
            @CustomDateOrigin = COALESCE(@CustomDateOrigin, 'PUPDEP'),
            @CustomDateSource = COALESCE(@CustomDateSource, 'CURRENT'),
            @ProcessOutbound204 = COALESCE(@ProcessOutbound204, 'N'),
            @Outbound204RailBilling = COALESCE(@Outbound204RailBilling, 'N'),
            @ValidateOutbound204 = COALESCE(@ValidateOutbound204, 'N'),
			@CarrierPlanned = COALESCE(@CarrierPlanned, 'N'),			
            @TractorDriverForPlanned = COALESCE(@TractorDriverForPlanned, 'N');
     IF @DisplayPendingOrders = 'Y'
         BEGIN
             INSERT INTO @PendingStatusCodes
                    SELECT LEFT(value, 6)
                    FROM CSVStringsToTable_fn(@PendingStatuses);
             IF NOT EXISTS
             (
                 SELECT 1
                 FROM @PendingStatusCodes
                 WHERE KeyField = 'PND'
             )
                 BEGIN
                     INSERT INTO @PendingStatusCodes
                            SELECT 'PND';
                 END;
         END;
     EXEC dbo.gettmwuser
          @tmwuser OUTPUT;
     SET @inbond = 0;
     IF
     (
         SELECT COUNT(ord_number)
         FROM orderheader WITH (NOLOCK)
         WHERE mov_number = @mov
               AND ord_status = 'CBR'
     ) > 0
         BEGIN
             SET @inbond = 1;
             UPDATE event
               SET
                   evt_status = 'OPN'
             WHERE evt_mov_number = @mov
                   AND evt_status = 'NON';
             UPDATE stops
               SET
                   stp_status = 'OPN',
                   stp_departure_status = 'OPN'
             WHERE mov_number = @mov
                   AND stp_status = 'NON';
         END;
     INSERT INTO @stpTable
            SELECT S.stp_number,
                   S.mov_number,
                   S.lgh_number,
                   S.ord_hdrnumber,
                   S.stp_mfh_sequence,
                   S.stp_arrivaldate,
                   S.stp_departuredate,
                   S.stp_status,
                   S.stp_departure_status,
                   S.stp_lgh_mileage,
                   S.stp_event,
                   S.stp_type,
                   S.stp_loadstatus,
                   S.cmd_code,
                   S.stp_description,
                   S.cmp_id,
                   S.stp_city,
                   S.stp_zipcode,
                   S.stp_schdtearliest,
                   S.stp_schdtlatest,
                   S.stp_transfer_type,
                   E.evt_driver1,
                   E.evt_driver2,
                   E.evt_tractor,
                   E.evt_trailer1,
                   E.evt_trailer2,
                   E.evt_trailer3,
                   E.evt_trailer4,
                   E.evt_dolly,
                   E.evt_dolly2,
                   E.evt_chassis,
                   E.evt_chassis2,
                   E.evt_carrier,
                   E.evt_hubmiles,
                   S.stp_lgh_mileage_mtid,
                   S.stp_ico_stp_number_parent
            FROM stops S WITH (NOLOCK)
                 INNER JOIN event E WITH (NOLOCK) ON E.stp_number = S.stp_number
                                                     AND E.evt_sequence = 1
            WHERE S.mov_number = @mov;
     INSERT INTO @evtTable
            SELECT event.evt_number,
                   event.stp_number,
                   event.evt_sequence,
                   COALESCE(event.ord_hdrnumber,stops.ord_hdrnumber)
            FROM event WITH (NOLOCK)
                 INNER JOIN stops WITH (NOLOCK) ON stops.stp_number = event.stp_number
            WHERE stops.mov_number = @mov
                  AND event.evt_sequence > 1;
     IF @inbond = 1
         BEGIN
             SELECT @inboundsequence = MAX(s.stp_mfh_sequence)
             FROM @stpTable s
                  INNER JOIN company c WITH (NOLOCK) ON c.cmp_id = s.cmp_id
             WHERE s.mov_number = @mov
                   AND s.stp_event IN('DLT', 'DRL')
                  AND c.cmp_isbond = 'Y';
             SELECT @inboundsequence = COALESCE(@inboundsequence, 0);
         END;
     IF @HazMatMileageLookups = 'Y'
        OR @HourlyPaywithBonus = '1'
        OR (@ProcessOutbound204 = 'Y'
            AND @Outbound204RailBilling = 'Y')
         INSERT INTO @updatemoveprocessingstops
                SELECT S.stp_number,
                       S.mov_number,
                       S.lgh_number,
                       S.ord_hdrnumber,
                       S.stp_mfh_sequence,
                       S.stp_event,
                       S.stp_type,
                       S.stp_arrivaldate,
                       S.stp_departuredate,
                       S.stp_status,
                       S.stp_departure_status,
                       S.stp_lgh_mileage_mtid,
                       S.evt_tractor,
                       S.evt_carrier,
                       S.cmp_id
                FROM @stpTable S;

     INSERT INTO @lghTable  -- legs that no longer have any stops
     (crud_type,
      lgh_number,
      lgh_carrier,
      lgh_204status,
      lgh_204validate
     )
            SELECT 'D',
                   lgh_number,
                   lgh_carrier,
                   lgh_204status,
                   lgh_204validate
            FROM legheader WITH (NOLOCK)
            WHERE mov_number = @mov
                  AND lgh_number NOT IN
            (
                SELECT lgh_number
                FROM @stpTable
            )
            UNION
            SELECT DISTINCT  -- legs that have stops with stp_status of NON
                   'D',
                   S.lgh_number,
                   l.lgh_carrier,
                   l.lgh_204status,
                   l.lgh_204validate
            FROM @stpTable S
                 LEFT JOIN legheader l WITH (NOLOCK) ON S.lgh_number = l.lgh_number
            WHERE stp_status = 'NON';

     SELECT TOP 1 @cmd_code = S.cmd_code,
                  @stp_description = S.stp_description
     FROM @stpTable S
     WHERE S.ord_hdrnumber > 0
           AND S.stp_description <> 'UNKNOWN';

     SELECT @legs = COUNT(DISTINCT(lgh_number))
     FROM @stpTable;
     WITH LegStopSequences
          AS (SELECT S.mov_number,
                     S.lgh_number,
                     StopInfo.MinSequence,
                     MAX(CASE
                             WHEN S.stp_mfh_sequence = StopInfo.MinSequence
                             THEN S.stp_number
                             ELSE 0
                         END) FirstStopNumber,
                     MAX(CASE
                             WHEN S.stp_mfh_sequence = StopInfo.MaxSequence
                             THEN S.stp_number
                             ELSE 0
                         END) LastStopNumber,
                     CASE
                         WHEN @UseOrdFromLeg = 'Y'
                              AND StopInfo.leg_ord_hdrnumber > 0
                         THEN StopInfo.leg_ord_hdrnumber
                         ELSE StopInfo.move_ord_hdrnumber
                     END ord_hdrnumber,
                     StopInfo.MinHubMiles,
                     StopInfo.MaxHubMiles,
                     StopInfo.LegMiles,
                     StopInfo.MpnCount
              FROM @stpTable S
                   LEFT OUTER JOIN @evtTable E ON E.stp_number = S.stp_number
                   INNER JOIN
              (
                  SELECT DISTINCT
                         S.lgh_number,
                         MAX(CASE
                                 WHEN S.ord_hdrnumber = 0
                                 THEN COALESCE(E.ord_hdrnumber, 0)
                                 ELSE S.ord_hdrnumber
                             END) OVER(PARTITION BY S.lgh_number) leg_ord_hdrnumber,
                         MAX(CASE
                                 WHEN S.ord_hdrnumber = 0
                                 THEN COALESCE(E.ord_hdrnumber, 0)
                                 ELSE S.ord_hdrnumber
                             END) OVER(PARTITION BY S.mov_number) move_ord_hdrnumber,
                         MIN(S.stp_mfh_sequence) OVER(PARTITION BY S.lgh_number) MinSequence,
                         MAX(S.stp_mfh_sequence) OVER(PARTITION BY S.lgh_number) MaxSequence,
                         MIN(CASE
                                 WHEN COALESCE(S.evt_hubmiles, 0) = 0
                                 THEN 2147483647
                                 ELSE S.evt_hubmiles
                             END) OVER(PARTITION BY S.lgh_number) MinHubMiles, -- using 2147483647 because we only want rows with values
                         MAX(CASE
                                 WHEN S.evt_hubmiles = 0
                                 THEN NULL
                                 ELSE S.evt_hubmiles
                             END) OVER(PARTITION BY S.lgh_number) MaxHubMiles,
                         Mileage.lgh_miles LegMiles,
                  (
                      SELECT COUNT(1)
                      FROM preplan_assets WITH (NOLOCK)
                      WHERE ppa_lgh_number = S.lgh_number
                            AND ppa_status = 'Active'
                  ) MpnCount
                  FROM @stpTable S
                       LEFT OUTER JOIN @evtTable E ON E.stp_number = S.stp_number
                       INNER JOIN
                  (
                      SELECT lgh_number,
                             SUM(COALESCE(stp_lgh_mileage, 0)) lgh_miles
                      FROM @stpTable
                      GROUP BY lgh_number
                  ) AS Mileage ON Mileage.lgh_number = S.lgh_number
              ) StopInfo ON StopInfo.lgh_number = S.lgh_number
              GROUP BY S.mov_number,
                       S.lgh_number,
                       StopInfo.MinSequence,
                       StopInfo.MinHubMiles,
                       StopInfo.MaxHubMiles,
                       StopInfo.LegMiles,
                       StopInfo.MpnCount,
                       CASE
                           WHEN @UseOrdFromLeg = 'Y'
                                AND StopInfo.leg_ord_hdrnumber > 0
                           THEN StopInfo.leg_ord_hdrnumber
                           ELSE StopInfo.move_ord_hdrnumber
                       END)
	, manifestOrderNumbers AS
	(
		SELECT
			MAX(manDet.ord_hdrnumber) orderHeaderNumber,
			legStopSeq.mov_number moveNumber
		FROM
			manifestdetail manDet
		INNER JOIN
			manifestheader mfh ON manDet.mfh_number = mfh.mfh_number
		INNER JOIN
			LegStopSequences legStopSeq ON mfh.mov_number = legStopSeq.mov_number
		WHERE
			legStopSeq.ord_hdrnumber = 0
		GROUP BY
			legStopSeq.mov_number
	)
          INSERT INTO @lghTable
          (crud_type,
           legsequence,
           legcount,
           lgh_number,
           ord_hdrnumber,
           mov_number,
           lgh_schdtearliest,
           lgh_schdtlatest,
           cmd_code,
           fgt_description,
           lgh_outstatus,
           lgh_instatus,
           lgh_fueltaxstatus,
           lgh_active,
           lgh_class1,
           lgh_class2,
           lgh_class3,
           lgh_class4,
           lgh_type1,
           lgh_type2,
           lgh_type3,
           lgh_type4,
           lgh_type5,
           cmp_id_start,
           lgh_startcty_nmstct,
           lgh_startcity,
           lgh_originzip,
           lgh_startlat,
           lgh_startlong,
           stp_number_start,
           lgh_startstate,
           lgh_startdate,
           lgh_startregion1,
           lgh_startregion2,
           lgh_startregion3,
           lgh_startregion4,
           cmp_id_end,
           lgh_endcty_nmstct,
           lgh_endcity,
           lgh_destzip,
           lgh_endlat,
           lgh_endlong,
           stp_number_end,
           lgh_endstate,
           lgh_enddate,
           lgh_enddate_arrival,
           lgh_endregion1,
           lgh_endregion2,
           lgh_endregion3,
           lgh_endregion4,
           lgh_driver1,
           lgh_driver2,
           mpp_teamleader,
           mpp_fleet,
           mpp_division,
           mpp_domicile,
           mpp_company,
           mpp_terminal,
           mpp_type1,
           mpp_type2,
           mpp_type3,
           mpp_type4,
           mpp2_type1,
           mpp2_type2,
           mpp2_type3,
           mpp2_type4,
           lgh_tractor,
           trc_company,
           trc_division,
           trc_teamleader,
           trc_fleet,
           trc_terminal,
           trc_type1,
           trc_type2,
           trc_type3,
           trc_type4,
           lgh_carrier,
           lgh_createdby,
           lgh_createdon,
           lgh_createapp,
           lgh_updatedby,
           lgh_updatedon,
           lgh_updateapp,
           lgh_odometerstart,
           lgh_odometerend,
           lgh_miles,
           lgh_route,
           lgh_direct_route_status1,
           lgh_booked_revtype1,
           lgh_204validate,
           lgh_split_flag,
           lgh_hzd_cmd_class,
           lgh_prev_seg_status,
           lgh_prev_seg_status_last_updated,
           lgh_plannedhours,
           lgh_raildispatchstatus,
		   lgh_refnum
          )
                 SELECT CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN 'C'
                            ELSE 'U'
                        END crud_type,
                        ROW_NUMBER() OVER(ORDER BY LSS.MinSequence) legsequence,
                        @legs legcount,
                        LSS.lgh_number,
                        CASE WHEN COALESCE(LSS.ord_hdrnumber, 0) = 0 THEN COALESCE(manOrdNum.orderHeaderNumber, 0) ELSE COALESCE(LSS.ord_hdrnumber, 0) END,
                        LSS.mov_number,
                        FS.stp_schdtearliest lgh_schdtearliest,
                        FS.stp_schdtlatest lgh_schdtlatest,
                        COALESCE(@cmd_code, 'UNK') cmd_code,
                        COALESCE(@stp_description, 'UNKNOWN') fgt_description,
                        CASE
                            WHEN @DisplayPendingOrders = 'Y'
                                 AND OH.ord_status = COALESCE(PSC.KeyField, 'XXX')
                            THEN OH.ord_status                            -- if order status is a pending status use order status
                            WHEN OH.ord_status = 'JOB'
                            THEN 'JOB'                                                                                            -- Status = JOB order status of JOB
                            WHEN FS.stp_transfer_type = 'SIT'
                            THEN 'SIT'                                                                                     -- Status = SIT have a stp_transfer_type = SIT
                            WHEN @CompleteOnDeparture = 'Y'
                                 AND LS.stp_departure_status = 'DNE'
                            THEN 'CMP'                                                   -- Status = CMP GI CompleteOnDeparture=Y and last stop departed
                                                              --NSUITE-203041 JJF 20171229 - use @CompleteOnDeparture...
                            WHEN @CompleteOnDeparture = 'N'
                                 AND LS.stp_status = 'DNE'
                            THEN 'CMP' 
                                                              --WHEN LS.stp_status = 'DNE' THEN 'CMP'                                                                                            -- Status = CMP GI CompleteOnDeparture<>Y and last stop arrived
                                                              --END NSUITE-203041 JJF 20171229 - use @CompleteOnDeparture...
                            WHEN FS.stp_status = 'DNE'
                            THEN 'STD'                                                                                            -- Status = STP not CMP and at least first stop arrived
                            WHEN @inbond = 1
                                 AND LS.stp_mfh_sequence > @inboundsequence
                            THEN 'PND'                                                           -- Status = PND inbound leg for inbond order
                            WHEN FS.evt_tractor <> 'UNKNOWN'
                                 OR -- have a tractor
                                 FS.evt_driver1 <> 'UNKNOWN'
                                 OR -- have a driver1
                                 FS.evt_driver2 <> 'UNKNOWN'
                                 OR -- have a driver2                                                                                      -- have a driver2
                                 FS.evt_carrier <> 'UNKNOWN'
                                 OR -- have a carrier
                                 LSS.MpnCount > 0
                            THEN                                                                                                       -- preplan_asset records exist
								  CASE
									  WHEN LGH.lgh_outstatus = 'DSP'
										THEN 'DSP' -- Status = DSP if was previously DSP
									  WHEN LSS.MpnCount > 0
										THEN 'MPN' -- Status = MPN if records in preplan_assets for leg
									  WHEN @TractorDriverForPlanned = 'Y' AND @CarrierPlanned = 'N' AND (FS.evt_tractor = 'UNKNOWN' OR FS.evt_driver1 = 'UNKNOWN')
										THEN 'AVL' -- Status = AVL when GI String1 for TractorDriverForPlanned=Y and don't have driver and tractor
									  WHEN @TractorDriverForPlanned = 'Y' AND @CarrierPlanned = 'Y' AND (FS.evt_tractor = 'UNKNOWN' OR FS.evt_driver1 = 'UNKNOWN') AND FS.evt_carrier = 'UNKNOWN'
										THEN 'AVL' -- Status = AVL when GI String1 for TractorDriverForPlanned=Y and Gi String2 for TractorDriverForPlanned=Y and don't have driver and tractor OR carrier.
									  ELSE 'PLN' -- Status = PLN have driver, tractor or carrier
								  END
                            ELSE 'AVL'                                                                                                                       -- Status = AVL no driver, tractor or carrier
                        END lgh_outstatus,
                        CASE
                            WHEN FS.stp_transfer_type = 'SIT'
                            THEN 'HST'                                                                                                                               -- InStatus = HST when lgh_outstatus is SIT
                            WHEN FS.evt_carrier <> 'UNKNOWN'
                                 AND Carrier.car_board = 'N'
                            THEN 'HST'                                                                                                    -- InStatus = HST non-board carrier assigned
                            WHEN FS.evt_carrier <> 'UNKNOWN'
                                 AND Carrier.car_board = 'Y'
                                 AND FS.evt_tractor <> 'UNKNOWN'
                                 AND @CompleteOnDeparture = 'Y'
                                 AND LS.stp_departure_status = 'DNE'
                            THEN 'HST' -- InStatus = HST board carrier and lgh_outstatus = CMP
                            WHEN FS.evt_carrier <> 'UNKNOWN'
                                 AND Carrier.car_board = 'Y'
                                 AND FS.evt_tractor <> 'UNKNOWN'
                                 AND @CompleteOnDeparture = 'N'
                                 AND LS.stp_status = 'DNE'
                            THEN 'HST'           -- InStatus = HST board carrier and lgh_outstatus = CMP
                            WHEN FS.evt_tractor <> 'UNKNOWN'
                                 AND
                 (
                     SELECT COUNT(1)                                                                                                                     -- InStatus = PLN when tractor assigned and has other legs planned
                     FROM assetassignment WITH (NOLOCK)
                     WHERE asgn_type = 'TRC'
                           AND asgn_id = FS.evt_tractor
                 ) > 0
                            THEN 'PLN'
                            ELSE 'UNP'                                                                                                                                                                 -- InStatus = UNP when no tractor assigned or tractor has no other planned legs
                        END lgh_instatus,
                        CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN 'NPD'  -- FuelTaxStatus = NPD for new legs
                            ELSE lgh_fueltaxstatus                           -- FuelTaxStatus not changed for existing legs
                        END lgh_fueltaxstatus,
                        CASE
                            WHEN FS.stp_transfer_type = 'SIT'
                            THEN 'N'                                                                                                                -- Active = N for lgh_outstatus of SIT
                            WHEN FS.evt_carrier <> 'UNKNOWN'
                                 AND (@CompleteOnDeparture = 'Y'
                                      OR @LghActiveUntilDepCompNBC = 'Y')
                                 AND LS.stp_departure_status = 'DNE'
                            THEN 'N'         -- Active = N carrier assigned anc lgh_outstatus of CMP
                            WHEN FS.evt_carrier <> 'UNKNOWN'
                                 AND (@CompleteOnDeparture = 'N'
                                      AND @LghActiveUntilDepCompNBC = 'N')
                                 AND LS.stp_status = 'DNE'
                            THEN 'N'                  -- Active = N carrier assigned anc lgh_outstatus of CMP
                            ELSE 'Y'                                                                                                                                                  -- Active for other cases instatus proc will fix as needed
                        END lgh_active,
                        CASE
                            WHEN LGH.lgh_manuallysettypeclass = 1
                            THEN LGH.lgh_class1 -- Class1 not changed if it has been manually edited
                            ELSE COALESCE(OH.ord_revtype1, 'UNK')                     -- Class1 = ord_revtype1 if not manually edited
                        END lgh_class1,
                        CASE
                            WHEN LGH.lgh_manuallysettypeclass = 1
                            THEN LGH.lgh_class2 -- Class2 not changed if it has been manually edited
                            ELSE COALESCE(OH.ord_revtype2, 'UNK')                     -- Class2 = ord_revtype2 if not manually edited
                        END lgh_class2,
                        CASE
                            WHEN LGH.lgh_manuallysettypeclass = 1
                            THEN LGH.lgh_class3 -- Class3 not changed if it has been manually edited
                            ELSE COALESCE(OH.ord_revtype3, 'UNK')                     -- Class3 = ord_revtype3 if not manually edited
                        END lgh_class3,
                        CASE
                            WHEN LGH.lgh_manuallysettypeclass = 1
                            THEN LGH.lgh_class4 -- Class4 not changed if it has been manually edited
                            ELSE COALESCE(OH.ord_revtype4, 'UNK')                     -- Class4 = ord_revtype4 if not manually edited
                        END lgh_class4,
                        COALESCE(LGH.lgh_type1, 'UNK') lgh_type1,
                        COALESCE(LGH.lgh_type2, 'UNK') lgh_type2,
                        COALESCE(LGH.lgh_type3, 'UNK') lgh_type3,
                        COALESCE(LGH.lgh_type4, 'UNK') lgh_type4,
                        COALESCE(LGH.lgh_type5, 'UNK') lgh_type5,
                        FS.cmp_id cmp_id_start,
                        FC.cty_nmstct lgh_startcty_nmstct,
                        FS.stp_city lgh_startcity,
                        FS.stp_zipcode lgh_originzip,
                        ROUND(COALESCE(FC.cty_latitude, 0), 0) lgh_startlat,
                        ROUND(COALESCE(FC.cty_longitude, 0), 0) lgh_startlong,
                        FS.stp_number stp_number_start,
                        FC.cty_state lgh_startstate,
                        FS.stp_arrivaldate lgh_startdate,
                        COALESCE(FC.cty_region1, 'UNK') lgh_startregion1,
                        COALESCE(FC.cty_region2, 'UNK') lgh_startregion2,
                        COALESCE(FC.cty_region3, 'UNK') lgh_startregion3,
                        COALESCE(FC.cty_region4, 'UNK') lgh_startregion4,
                        LS.cmp_id cmp_id_end,
                        LC.cty_nmstct lgh_endcty_nmstct,
                        LS.stp_city lgh_endcity,
                        LS.stp_zipcode lgh_destzip,
                        ROUND(COALESCE(LC.cty_latitude, 0), 0) lgh_endlat,
                        ROUND(COALESCE(LC.cty_longitude, 0), 0) lgh_endlong,
                        LS.stp_number stp_number_end,
                        LC.cty_state lgh_endstate,
                        LS.stp_departuredate lgh_enddate,
                        LS.stp_arrivaldate lgh_enddate_arrival,
                        COALESCE(LC.cty_region1, 'UNK') lgh_endregion1,
                        COALESCE(LC.cty_region2, 'UNK') lgh_endregion2,
                        COALESCE(LC.cty_region3, 'UNK') lgh_endregion3,
                        COALESCE(LC.cty_region4, 'UNK') lgh_endregion4,
                        FS.evt_driver1 lgh_driver1,
                        FS.evt_driver2 lgh_driver2,
                        Driver1.mpp_teamleader mpp_teamleader,
                        Driver1.mpp_fleet mpp_fleet,
                        Driver1.mpp_division mpp_division,
                        Driver1.mpp_domicile mpp_domicile,
                        Driver1.mpp_company mpp_company,
                        Driver1.mpp_terminal mpp_terminal,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                    -- MppType1 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                         -- Don't change MppType1 once CMP unless driver1 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver1.mpp_id = LGH.lgh_driver1
                                     THEN LGH.mpp_type1             -- MppType1 not changed for CMP and same driver1
                                     ELSE Driver1.mpp_type1                                                                                                                                                                                -- MppType1 set to Driver1 mpp_type1 when not CMP or new legs
                                 END
                                     ELSE Driver1.mpp_type1                                                                                                                                                                                    -- MppType1 set to Driver1 mpp_type1
                                 END
                                     ELSE LGH.mpp_type1                                                                                                                                                                                            -- MppTypes have been manually set don't change
                                 END, 'UNK') mpp_type1,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                    -- MppType2 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                         -- Don't change MppType2 once CMP unless driver1 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver1.mpp_id = LGH.lgh_driver1
                                     THEN LGH.mpp_type2             -- MppType2 not changed for CMP and same driver1
                                     ELSE Driver1.mpp_type2                                                                                                                                                                                -- MppType2 set to Driver1 mpp_type2 when not CMP or new legs
                                 END
                                     ELSE Driver1.mpp_type2                                                                                                                                                                                    -- MppType2 set to Driver1 mpp_type2
                                 END
                                     ELSE LGH.mpp_type2                                                                                                                                                                                            -- MppTypes have been manually set don't change
                                 END, 'UNK') mpp_type2,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                    -- MppType3 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                         -- Don't change MppType3 once CMP unless driver1 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver1.mpp_id = LGH.lgh_driver1
                                     THEN LGH.mpp_type3             -- MppType3 not changed for CMP and same driver1
                                     ELSE Driver1.mpp_type3                                                                                                                                                                                -- MppType3 set to Driver1 mpp_type3 when not CMP or new legs
                                 END
                                     ELSE Driver1.mpp_type3                                                                                                                                                                                    -- MppType3 set to Driver1 mpp_type3
                                 END
                                     ELSE LGH.mpp_type3                                                                                                                                                                                            -- MppTypes have been manually set don't change
                                 END, 'UNK') mpp_type3,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                    -- MppType4 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                         -- Don't change MppType4 once CMP unless driver1 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver1.mpp_id = LGH.lgh_driver1
                                     THEN LGH.mpp_type4             -- MppType4 not changed for CMP and same driver1
                                     ELSE Driver1.mpp_type4                                                                                                                                                                                -- MppType4 set to Driver1 mpp_type4 when not CMP or new legs
                                 END
                                     ELSE Driver1.mpp_type4                                                                                                                                                                                    -- MppType4 set to Driver1 mpp_type4
                                 END
                                     ELSE LGH.mpp_type4                                                                                                                                                                                            -- MppTypes have been manually set don't change
                                 END, 'UNK') mpp_type4,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                     -- Mpp2Type1 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                          -- Don't change Mpp2Type1 once CMP unless driver2 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver2.mpp_id = LGH.lgh_driver2
                                     THEN LGH.mpp2_type1             -- Mpp2Type1 not changed for CMP and same driver2
                                     ELSE Driver2.mpp_type1                                                                                                                                                                                 -- Mpp2Type1 set to Driver2 mpp_type1 when not CMP or new legs
                                 END
                                     ELSE Driver2.mpp_type1                                                                                                                                                                                     -- Mpp2Type1 set to Driver1 mpp_type1
                                 END
                                     ELSE LGH.mpp2_type1                                                                                                                                                                                            -- Mpp2Types have been manually set don't change
                                 END, 'UNK') mpp2_type1,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                     -- Mpp2Type2 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                          -- Don't change Mpp2Type2 once CMP unless driver2 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver2.mpp_id = LGH.lgh_driver2
                                     THEN LGH.mpp2_type2             -- Mpp2Type2 not changed for CMP and same driver2
                                     ELSE Driver2.mpp_type2                                                                                                                                                                                 -- Mpp2Type2 set to Driver2 mpp_type2 when not CMP or new legs
                                 END
                                     ELSE Driver2.mpp_type2                                                                                                                                                                                     -- Mpp2Type2 set to Driver2 mpp_type2
                                 END
                                     ELSE LGH.mpp2_type2                                                                                                                                                                                            -- Mpp2Types have been manually set don't change
                                 END, 'UNK') mpp2_type2,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                     -- Mpp2Type3 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                          -- Don't change Mpp2Type3 once CMP unless driver2 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver2.mpp_id = LGH.lgh_driver2
                                     THEN LGH.mpp2_type3             -- Mpp2Type3 not changed for CMP and same driver2
                                     ELSE Driver2.mpp_type3                                                                                                                                                                                 -- Mpp2Type3 set to Driver2 mpp_type3 when not CMP or new legs
                                 END
                                     ELSE Driver2.mpp_type3                                                                                                                                                                                     -- Mpp2Type3 set to Driver2 mpp_type3
                                 END
                                     ELSE LGH.mpp2_type3                                                                                                                                                                                            -- Mpp2Types have been manually set don't change
                                 END, 'UNK') mpp2_type3,
                        COALESCE(CASE
                                     WHEN COALESCE(lgh_mpp_type_editdatetime, CONVERT( DATETIME, 0)) = CONVERT(DATETIME, 0)
                                     THEN                                                                                                                     -- Mpp2Type4 has not been manually set
                                 CASE
                                     WHEN @FixMppTypesOnCmp = 'Y'
                                     THEN                                                                                                                                                                          -- Don't change Mpp2Type4 once CMP unless driver2 changes
                                 CASE
                                     WHEN((@CompleteOnDeparture = 'Y'
                                           AND LS.stp_departure_status = 'DNE')
                                          OR (@CompleteOnDeparture = 'N'
                                              AND LS.stp_status = 'DNE'))
                                         AND Driver2.mpp_id = LGH.lgh_driver2
                                     THEN LGH.mpp2_type4             -- Mpp2Type4 not changed for CMP and same driver2
                                     ELSE Driver2.mpp_type4                                                                                                                                                                                 -- Mpp2Type4 set to Driver2 mpp_type4 when not CMP or new legs
                                 END
                                     ELSE Driver2.mpp_type4                                                                                                                                                                                     -- Mpp2Type4 set to Driver2 mpp_type4
                                 END
                                     ELSE LGH.mpp2_type4                                                                                                                                                                                            -- Mpp2Types have been manually set don't change
                                 END, 'UNK') mpp2_type4,
                        FS.evt_tractor lgh_tractor,
                        Tractor.trc_company trc_company,
                        Tractor.trc_division trc_division,
                        Tractor.trc_teamleader trc_teamleader,
                        Tractor.trc_fleet trc_fleet,
                        Tractor.trc_terminal trc_terminal,
                        COALESCE(CASE
                                     WHEN @FixTrcTypesOnCmp = 'Y'
                                     THEN CASE
                                              WHEN((@CompleteOnDeparture = 'Y'
                                                    AND LS.stp_departure_status = 'DNE')
                                                   OR (@CompleteOnDeparture = 'N'
                                                       AND LS.stp_status = 'DNE'))
                                                  AND Tractor.trc_number = LGH.lgh_tractor
                                              THEN LGH.trc_type1
                                              ELSE Tractor.trc_type1
                                          END
                                     ELSE Tractor.trc_type1
                                 END, 'UNK') trc_type1,
                        COALESCE(CASE
                                     WHEN @FixTrcTypesOnCmp = 'Y'
                                     THEN CASE
                                              WHEN((@CompleteOnDeparture = 'Y'
                                                    AND LS.stp_departure_status = 'DNE')
                                                   OR (@CompleteOnDeparture = 'N'
                                                       AND LS.stp_status = 'DNE'))
                                                  AND Tractor.trc_number = LGH.lgh_tractor
                                              THEN LGH.trc_type2
                                              ELSE Tractor.trc_type2
                                          END
                                     ELSE Tractor.trc_type2
                                 END, 'UNK') trc_type2,
                        COALESCE(CASE
                                     WHEN @FixTrcTypesOnCmp = 'Y'
                                     THEN CASE
                                              WHEN((@CompleteOnDeparture = 'Y'
                                                    AND LS.stp_departure_status = 'DNE')
                                                   OR (@CompleteOnDeparture = 'N'
                                                       AND LS.stp_status = 'DNE'))
                                                  AND Tractor.trc_number = LGH.lgh_tractor
                                              THEN LGH.trc_type3
                                              ELSE Tractor.trc_type3
                                          END
                                     ELSE Tractor.trc_type3
                                 END, 'UNK') trc_type3,
                        COALESCE(CASE
                                     WHEN @FixTrcTypesOnCmp = 'Y'
                                     THEN CASE
                                              WHEN((@CompleteOnDeparture = 'Y'
                                                    AND LS.stp_departure_status = 'DNE')
                                                   OR (@CompleteOnDeparture = 'N'
                                                       AND LS.stp_status = 'DNE'))
                                                  AND Tractor.trc_number = LGH.lgh_tractor
                                              THEN LGH.trc_type4
                                              ELSE Tractor.trc_type4
                                          END
                                     ELSE Tractor.trc_type4
                                 END, 'UNK') trc_type4,
                        FS.evt_carrier lgh_carrier,
                        CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN @tmwuser   -- new leg set lgh_createdby
                            ELSE LGH.lgh_createdby
                        END lgh_createdby,
                        CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN GETDATE()  -- new leg set lgh_createdon
                            ELSE LGH.lgh_createdon
                        END lgh_createdon,
                        CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN APP_NAME() -- new leg set lgh_createapp
                            ELSE LGH.lgh_createapp
                        END lgh_createapp,
                        @tmwuser lgh_updatedby,
                        GETDATE() lgh_updatedon,
                        APP_NAME() lgh_updateapp,
                        CASE
                            WHEN LSS.MinHubMiles = 2147483647
                            THEN NULL  -- 2147483647 means no rows actually had hub miles entered
                            ELSE LSS.MinHubMiles
                        END lgh_odometerstart,
                        LSS.MaxHubMiles lgh_odometerend,
                        LSS.LegMiles lgh_miles,
                        COALESCE(OH.ord_route, 'UNKNOWN') lgh_route,
                        COALESCE(LGH.lgh_direct_route_status1, 'NSNT') lgh_direct_route_status1, -- No longer checks GI setting, always set on new legheaders
                        CASE
                            WHEN COALESCE(LGH.lgh_number, 0) = 0
                            THEN                                 -- new leg
                                                                       CASE
                                                                           WHEN COALESCE(OH.ord_broker, '') <> ''
                                                                           THEN OH.ord_broker             -- if ord_broker is set use it
                                                                           WHEN @DefaultLghBookedRevType1 <> ''
                                                                           THEN @DefaultLghBookedRevType1   -- if default booked revtype1 is set use it
                                                                           ELSE COALESCE(OH.ord_booked_revtype1, 'UNKNOWN')
                                                                       END
                            WHEN @DefaultLghBookedRevType1 <> ''
                                 AND (LGH.lgh_booked_revtype1 = ''
                                      OR COALESCE(LGH.lgh_booked_revtype1, 'UNKNOWN') = 'UNKNOWN')
                            THEN @DefaultLghBookedRevType1  -- existing leg booked revtype1 not set and you have a default
                            ELSE LGH.lgh_booked_revtype1
                        END lgh_booked_revtype1,
                        CASE
                            WHEN @ProcessOutbound204 = 'Y'
                                 AND @ValidateOutbound204 = 'Y'
                                 AND FS.evt_carrier <> 'UNKNOWN'
                            THEN                                  -- Doing 204s, 204 validation and has carrier
                            CASE
                                WHEN COALESCE(Carrier.car_204flag, 0) = 1
                                THEN                                                                                  -- carrier does 204s
                            CASE
                                WHEN COALESCE(LGH.lgh_number, 0) = 0
                                THEN                                                                                   -- new leg 
                            CASE
                                WHEN COALESCE(Carrier.car_204validate, 0) = 0
                                THEN 1                                                                    -- carrier does not require validation set to validated
                                WHEN COALESCE(Carrier.car_204validate, 0) = 1
                                THEN 0                                                                    -- carrier requrires validation set to needs validation
                                ELSE NULL
                            END
                                ELSE                                                                                                                        -- existing leg
                            CASE
                                WHEN COALESCE(Carrier.car_204validate, 0) = 0
                                THEN 1                                                                    -- carrier does not require validation set to validated 
                                WHEN COALESCE(Carrier.car_204validate, 0) = 1
                                     AND LGH.lgh_204validate = 1
                                     AND Carrier.car_id <> LGH.lgh_carrier
                                THEN 0  -- was validated by carrier changed and carrier requires validation set to needs validation
                                WHEN COALESCE(Carrier.car_204validate, 0) = 1
                                THEN COALESCE(LGH.lgh_204validate, 0)                                     -- carrier needs validation but carrier didn't change leave field alone
                                ELSE NULL
                            END
                            END
                                ELSE NULL
                            END
                            ELSE NULL
                        END lgh_204validate,
                        CASE                                   -- replaces set_split_flag stored procedure logic
                            WHEN @legs = 1
                            THEN 'N'              -- only one leg on move
                            ELSE 'S'                             -- move has more than one leg this is not the last
                        END lgh_split_flag,
                        NULL lgh_hzd_cmd_class,
                        LGH.lgh_prev_seg_status lgh_prev_seg_status,
                        LGH.lgh_prev_seg_status_last_updated lgh_prev_seg_status_last_updated,
                        NULL lgh_plannedhours,
                        LGH.lgh_raildispatchstatus,
						LGH.lgh_refnum
                 FROM LegStopSequences LSS
                      INNER JOIN @stpTable FS ON FS.stp_number = LSS.FirstStopNumber
                      INNER JOIN city FC WITH (NOLOCK) ON FC.cty_code = FS.stp_city
                      INNER JOIN @stpTable LS ON LS.stp_number = LSS.LastStopNumber
                      INNER JOIN city LC WITH (NOLOCK) ON LC.cty_code = LS.stp_city
                      LEFT OUTER JOIN legheader LGH WITH (NOLOCK) ON LGH.lgh_number = LSS.lgh_number
                      LEFT OUTER JOIN orderheader OH WITH (NOLOCK) ON OH.ord_hdrnumber = LSS.ord_hdrnumber
                      INNER JOIN Carrier WITH (NOLOCK) ON Carrier.car_id = FS.evt_carrier
                      INNER JOIN manpowerprofile Driver1 WITH (NOLOCK) ON Driver1.mpp_id = FS.evt_driver1
                      INNER JOIN manpowerprofile Driver2 WITH (NOLOCK) ON Driver2.mpp_id = FS.evt_driver2
                      INNER JOIN tractorprofile Tractor WITH (NOLOCK) ON Tractor.trc_number = FS.evt_tractor
                      LEFT OUTER JOIN @PendingStatusCodes PSC ON PSC.KeyField = OH.ord_status
					  LEFT JOIN manifestOrderNumbers manOrdNum ON manOrdNum.moveNumber = LSS.mov_number
                 WHERE LSS.lgh_number NOT IN
											(
												SELECT lgh_number
												FROM @lghTable
											) 
						--PB-200513 JJF 20190425 Don't create legheader entries if non dispatchable stops are present
						AND NOT EXISTS	(	SELECT	* 
											FROM	@stpTable st 
											WHERE	COALESCE(LGH.lgh_number, 0) = 0 
													AND st.lgh_number = LSS.lgh_number 
													AND st.stp_status = 'NON'
										)
				 ;

     WITH LegOrderStopSequences
          AS (SELECT DISTINCT
                     S.lgh_number,
                     FIRST_VALUE(stp_number) OVER(PARTITION BY S.lgh_number ORDER BY S.stp_mfh_sequence,
                                                                                     S.stp_arrivaldate) FirstBillableStopNumber,
                     LAST_VALUE(stp_number) OVER(PARTITION BY S.lgh_number ORDER BY S.stp_mfh_sequence,
                                                                                    S.stp_arrivaldate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) LastBillableStopNumber
              FROM @stpTable S
              WHERE S.ord_hdrnumber > 0)
          UPDATE LGH
            SET
                LGH.cmp_id_rstart = FS.cmp_id,
                LGH.lgh_rstartcty_nmstct = FC.cty_nmstct,
                LGH.lgh_rstartcity = FS.stp_city,
                LGH.lgh_rstartlat = ROUND(FC.cty_latitude, 0),
                LGH.lgh_rstartlong = ROUND(FC.cty_longitude, 0),
                LGH.stp_number_rstart = FS.stp_number,
                LGH.lgh_rstartstate = FC.cty_state,
                LGH.lgh_rstartdate = FS.stp_arrivaldate,
                LGH.lgh_rstartregion1 = FC.cty_region1,
                LGH.lgh_rstartregion2 = FC.cty_region2,
                LGH.lgh_rstartregion3 = FC.cty_region3,
                LGH.lgh_rstartregion4 = FC.cty_region4,
                LGH.cmp_id_rend = LS.cmp_id,
                LGH.lgh_rendcty_nmstct = LC.cty_nmstct,
                LGH.lgh_rendcity = LS.stp_city,
                LGH.lgh_rendlat = ROUND(LC.cty_latitude, 0),
                LGH.lgh_rendlong = ROUND(LC.cty_longitude, 0),
                LGH.stp_number_rend = LS.stp_number,
                LGH.lgh_rendstate = LC.cty_state,
                LGH.lgh_renddate = LS.stp_departuredate,
                LGH.lgh_rendregion1 = LC.cty_region1,
                LGH.lgh_rendregion2 = LC.cty_region2,
                LGH.lgh_rendregion3 = LC.cty_region3,
                LGH.lgh_rendregion4 = LC.cty_region4
          FROM @lghTable LGH
               LEFT OUTER JOIN LegOrderStopSequences LOSS ON LOSS.lgh_number = LGH.lgh_number
               LEFT OUTER JOIN @stpTable FS ON FS.stp_number = LOSS.FirstBillableStopNumber
               LEFT OUTER JOIN city FC WITH (NOLOCK) ON FC.cty_code = FS.stp_city
               LEFT OUTER JOIN @stpTable LS ON LS.stp_number = LOSS.LastBillableStopNumber
               LEFT OUTER JOIN city LC WITH (NOLOCK) ON LC.cty_code = LS.stp_city
          WHERE LGH.crud_type IN('C', 'U');


     WITH LegLoadedStopSequence
          AS (SELECT DISTINCT
                     S.lgh_number,
                     FIRST_VALUE(S.stp_number) OVER(PARTITION BY S.lgh_number ORDER BY S.stp_mfh_sequence,
                                                                                       S.stp_arrivaldate) FirstLoadedStopNumber
              FROM @stpTable S
                   INNER JOIN @lghTable LGH ON LGH.lgh_number = S.lgh_number
              WHERE S.stp_type = 'PUP'
                    OR S.stp_event IN('HCT', 'HLT')
                   OR (S.stp_loadstatus = 'LD'
                       AND S.stp_number <> LGH.stp_number_start) -- fist stop can't be loaded
     ),
          LegTrailerStopSequence
          AS (SELECT DISTINCT
                     S.lgh_number,
                     FIRST_VALUE(S.stp_number) OVER(PARTITION BY S.lgh_number ORDER BY S.stp_mfh_sequence ASC,
                                                                                       S.stp_arrivaldate ASC) FirstTrailerStopNumber
              FROM @stpTable S
              WHERE S.evt_trailer1 <> 'UNKNOWN'),
          TrailerStop
          AS (SELECT LGH.lgh_number,
                     CASE
                         WHEN COALESCE(LLSS.FirstLoadedStopNumber, 0) > 0
                         THEN LLSS.FirstLoadedStopNumber
                         WHEN COALESCE(LTSS.FirstTrailerStopNumber, 0) > 0
                         THEN LTSS.FirstTrailerStopNumber
                         ELSE LGH.stp_number_start
                     END TrailerStopNumber
              FROM @lghTable LGH
                   LEFT OUTER JOIN LegLoadedStopSequence LLSS ON LLSS.lgh_number = LGH.lgh_number
                   LEFT OUTER JOIN LegTrailerStopSequence LTSS ON LTSS.lgh_number = LGH.lgh_number
              WHERE LGH.crud_type IN('C', 'U'))
          UPDATE LGH
            SET
                LGH.lgh_primary_trailer = S.evt_trailer1,
                LGH.lgh_primary_pup = S.evt_trailer2,
                LGH.lgh_trailer3 = S.evt_trailer3,
                LGH.lgh_trailer4 = S.evt_trailer4,
                LGH.lgh_chassis = S.evt_chassis,
                LGH.lgh_chassis2 = S.evt_chassis2,
                LGH.lgh_dolly = S.evt_dolly,
                LGH.lgh_dolly2 = S.evt_dolly2,
                LGH.trl_company = Trailer.trl_company,
                LGH.trl_fleet = Trailer.trl_fleet,
                LGH.trl_division = Trailer.trl_division,
                LGH.trl_terminal = Trailer.trl_terminal,
                LGH.trl_type1 = Trailer.trl_type1,
                LGH.trl_type2 = Trailer.trl_type2,
                LGH.trl_type3 = Trailer.trl_type3,
                LGH.trl_type4 = Trailer.trl_type4
          FROM @lghTable LGH
               INNER JOIN TrailerStop TS ON TS.lgh_number = LGH.lgh_number
               INNER JOIN @stpTable S ON S.stp_number = TS.TrailerStopNumber
               INNER JOIN trailerprofile Trailer WITH (NOLOCK) ON Trailer.trl_id = S.evt_trailer1;

     WITH Orders
          AS -- gets distinct orders on for legs (needed for order totals going against stops only was duping totals for each ordre stop)
          (SELECT DISTINCT
                  S.mov_number,
                  S.lgh_number,
                  CASE
                      WHEN S.ord_hdrnumber = 0
                      THEN COALESCE(E.ord_hdrnumber, 0)
                      ELSE S.ord_hdrnumber
                  END ord_hdrnumber
           FROM @stpTable S
                LEFT OUTER JOIN @evtTable E ON E.stp_number = S.stp_number),
          OrderInfo
          AS (SELECT DISTINCT
                     O.lgh_number,
                     MIN(OH.ord_priority) OVER(PARTITION BY O.mov_number) MinOrderPriority,
                     SUM(COALESCE(ord_totalcharge, 0)) OVER(PARTITION BY O.lgh_number) Linehaul,
                     SUM(COALESCE(ord_charge, 0)) OVER(PARTITION BY O.lgh_number) OrderCharge,
                     SUM(COALESCE(ord_totalweight, 0)) OVER(PARTITION BY O.lgh_number) EstimatedWeight,
                     SUM(COALESCE(ord_tareweight, 0)) OVER(PARTITION BY O.lgh_number) ActualWeight,
                     SUM(COALESCE(NULLIF(ord_tareweight, 0), COALESCE(ord_totalweight, 0))) OVER(PARTITION BY O.lgh_number) TotalWeight
              FROM Orders O
                   LEFT OUTER JOIN orderheader OH WITH (NOLOCK) ON OH.ord_hdrnumber = O.ord_hdrnumber)
          UPDATE LGH
            SET
                LGH.lgh_priority = OI.MinOrderPriority,
                LGH.lgh_linehaul = OI.Linehaul,
                LGH.lgh_ord_charge = OI.OrderCharge,
                LGH.lgh_act_weight = OI.ActualWeight,
                LGH.lgh_est_weight = OI.EstimatedWeight,
                LGH.lgh_tot_weight = OI.TotalWeight
          FROM @lghTable LGH
               LEFT OUTER JOIN OrderInfo OI ON OI.lgh_number = LGH.lgh_number
          WHERE LGH.crud_type IN('C', 'U');

     UPDATE LGH
       SET
           LGH.lgh_reftype = R.ref_type,
           LGH.lgh_refnum = COALESCE(R.ref_number, LGH.lgh_refnum),
           LGH.lgh_split_flag = CASE
                                    WHEN LGH.legcount > 1
                                         AND LGH.legsequence = LGH.legcount
                                    THEN 'F'   -- last leg on move with more than one leg
                                    ELSE LGH.lgh_split_flag
                                END
     FROM @lghTable LGH
          LEFT OUTER JOIN referencenumber R WITH (NOLOCK) ON R.ref_table = 'legheader'
                                                             AND R.ref_tablekey = LGH.lgh_number
                                                             AND R.ref_sequence = 1;

     IF(@ProcessOutbound204 = 'Y'
        AND @Outbound204RailBilling = 'Y')
       OR @PreviousSegmentStatus = 'Y'
       OR (@HourlyPaywithBonus = '1')
         INSERT INTO @updatemoveprocessinglegs
                SELECT L.lgh_number,
                       L.mov_number,
                       L.legcount,
                       L.legsequence,
                       L.stp_number_start,
                       L.stp_number_end
                FROM @lghTable L
                WHERE L.crud_type IN('C', 'U');

     IF @HazMatMileageLookups = 'Y'
         BEGIN
             UPDATE LGH
               SET
                   LGH.lgh_hzd_cmd_class = LHCC.cmd_class
             FROM @lghTable LGH
                  INNER JOIN dbo.UpdateMoveProcessing_HazMatMileageLookups_fn(@updatemoveprocessingstops) LHCC ON LHCC.lgh_number = LGH.lgh_number
             WHERE LGH.crud_type IN('C', 'U');
         END;

     IF @PreviousSegmentStatus = 'Y'
         BEGIN
             UPDATE LGH
               SET
                   LGH.lgh_prev_seg_status = PS.PreviousSegmentStatus,
                   LGH.lgh_prev_seg_status_last_updated = GETDATE()
             FROM @lghTable LGH
                  INNER JOIN dbo.UpdateMoveProcessing_PreviousSegmentStatus_fn(@updatemoveprocessingstops, @updatemoveprocessinglegs) PS ON PS.lgh_number = LGH.lgh_number
             WHERE LGH.crud_type IN('C', 'U')
             AND COALESCE(LGH.lgh_prev_seg_status, 'XXX') <> COALESCE(PS.PreviousSegmentStatus, 'XXX');
         END;

     IF @HourlyPaywithBonus = '1'
         BEGIN
             UPDATE LGH
               SET
                   lgh_plannedhours = LPT.PlannedHours
             FROM @lghTable LGH
                  INNER JOIN dbo.UpdateMoveProcessing_HourlyPaywithBonus_fn(@updatemoveprocessingstops) LPT ON LPT.lgh_number = LGH.lgh_number
             WHERE LGH.crud_type IN('C', 'U');
         END;

     IF @ProcessOutbound204 = 'Y'
        AND @Outbound204RailBilling = 'Y'
         BEGIN
             UPDATE LGH
               SET
                   lgh_raildispatchstatus = ORB.RailDispatchStatus
             FROM @lghTable LGH
                  LEFT OUTER JOIN dbo.UpdateMoveProcessing_Outbound204RailBilling_fn(@updatemoveprocessingstops, @updatemoveprocessinglegs) ORB ON ORB.lgh_number = LGH.lgh_number;
         END;

	IF EXISTS	(	SELECT	*
					FROM	@lghTable
					WHERE	crud_type = 'C'
				) BEGIN

		 INSERT INTO legheader
		 (lgh_number,
		  ord_hdrnumber,
		  mov_number,
		  lgh_priority,
		  lgh_schdtearliest,
		  lgh_schdtlatest,
		  cmd_code,
		  fgt_description,
		  lgh_outstatus,
		  lgh_instatus,
		  lgh_fueltaxstatus,
		  lgh_active,
		  lgh_class1,
		  lgh_class2,
		  lgh_class3,
		  lgh_class4,
		  lgh_type1,
		  lgh_type2,
		  lgh_type3,
		  lgh_type4,
		  lgh_type5,
		  cmp_id_start,
		  lgh_startcty_nmstct,
		  lgh_startcity,
		  lgh_originzip,
		  lgh_startlat,
		  lgh_startlong,
		  stp_number_start,
		  lgh_startstate,
		  lgh_startdate,
		  lgh_startregion1,
		  lgh_startregion2,
		  lgh_startregion3,
		  lgh_startregion4,
		  cmp_id_end,
		  lgh_endcty_nmstct,
		  lgh_endcity,
		  lgh_destzip,
		  lgh_endlat,
		  lgh_endlong,
		  stp_number_end,
		  lgh_endstate,
		  lgh_enddate,
		  lgh_enddate_arrival,
		  lgh_endregion1,
		  lgh_endregion2,
		  lgh_endregion3,
		  lgh_endregion4,
		  lgh_driver1,
		  lgh_driver2,
		  mpp_teamleader,
		  mpp_fleet,
		  mpp_division,
		  mpp_domicile,
		  mpp_company,
		  mpp_terminal,
		  mpp_type1,
		  mpp_type2,
		  mpp_type3,
		  mpp_type4,
		  mpp2_type1,
		  mpp2_type2,
		  mpp2_type3,
		  mpp2_type4,
		  lgh_tractor,
		  trc_company,
		  trc_division,
		  trc_teamleader,
		  trc_fleet,
		  trc_terminal,
		  trc_type1,
		  trc_type2,
		  trc_type3,
		  trc_type4,
		  lgh_primary_trailer,
		  lgh_primary_pup,
		  lgh_trailer3,
		  lgh_trailer4,
		  lgh_chassis,
		  lgh_chassis2,
		  lgh_dolly,
		  lgh_dolly2,
		  trl_company,
		  trl_fleet,
		  trl_division,
		  trl_terminal,
		  trl_type1,
		  trl_type2,
		  trl_type3,
		  trl_type4,
		  lgh_carrier,
		  lgh_createdby,
		  lgh_createdon,
		  lgh_createapp,
		  lgh_updatedby,
		  lgh_updatedon,
		  lgh_updateapp,
		  lgh_odometerstart,
		  lgh_odometerend,
		  cmp_id_rstart,
		  lgh_rstartcty_nmstct,
		  lgh_rstartcity,
		  lgh_rstartlat,
		  lgh_rstartlong,
		  stp_number_rstart,
		  lgh_rstartstate,
		  lgh_rstartdate,
		  lgh_rstartregion1,
		  lgh_rstartregion2,
		  lgh_rstartregion3,
		  lgh_rstartregion4,
		  cmp_id_rend,
		  lgh_rendcty_nmstct,
		  lgh_rendcity,
		  lgh_rendlat,
		  lgh_rendlong,
		  stp_number_rend,
		  lgh_rendstate,
		  lgh_renddate,
		  lgh_rendregion1,
		  lgh_rendregion2,
		  lgh_rendregion3,
		  lgh_rendregion4,
		  lgh_miles,
		  lgh_reftype,
		  lgh_refnum,
		  lgh_linehaul,
		  lgh_ord_charge,
		  lgh_act_weight,
		  lgh_est_weight,
		  lgh_tot_weight,
		  lgh_route,
		  lgh_direct_route_status1,
		  lgh_booked_revtype1,
		  lgh_204validate,
		  lgh_split_flag,
		  lgh_hzd_cmd_class,
		  lgh_prev_seg_status,
		  lgh_prev_seg_status_last_updated,
		  lgh_plannedhours,
		  lgh_raildispatchstatus
		 )
				SELECT lgh_number,
					   ord_hdrnumber,
					   mov_number,
					   lgh_priority,
					   lgh_schdtearliest,
					   lgh_schdtlatest,
					   cmd_code,
					   fgt_description,
					   lgh_outstatus,
					   lgh_instatus,
					   lgh_fueltaxstatus,
					   lgh_active,
					   lgh_class1,
					   lgh_class2,
					   lgh_class3,
					   lgh_class4,
					   lgh_type1,
					   lgh_type2,
					   lgh_type3,
					   lgh_type4,
					   lgh_type5,
					   cmp_id_start,
					   lgh_startcty_nmstct,
					   lgh_startcity,
					   lgh_originzip,
					   lgh_startlat,
					   lgh_startlong,
					   stp_number_start,
					   lgh_startstate,
					   lgh_startdate,
					   lgh_startregion1,
					   lgh_startregion2,
					   lgh_startregion3,
					   lgh_startregion4,
					   cmp_id_end,
					   lgh_endcty_nmstct,
					   lgh_endcity,
					   lgh_destzip,
					   lgh_endlat,
					   lgh_endlong,
					   stp_number_end,
					   lgh_endstate,
					   lgh_enddate,
					   lgh_enddate_arrival,
					   lgh_endregion1,
					   lgh_endregion2,
					   lgh_endregion3,
					   lgh_endregion4,
					   lgh_driver1,
					   lgh_driver2,
					   mpp_teamleader,
					   mpp_fleet,
					   mpp_division,
					   mpp_domicile,
					   mpp_company,
					   mpp_terminal,
					   mpp_type1,
					   mpp_type2,
					   mpp_type3,
					   mpp_type4,
					   mpp2_type1,
					   mpp2_type2,
					   mpp2_type3,
					   mpp2_type4,
					   lgh_tractor,
					   trc_company,
					   trc_division,
					   trc_teamleader,
					   trc_fleet,
					   trc_terminal,
					   trc_type1,
					   trc_type2,
					   trc_type3,
					   trc_type4,
					   lgh_primary_trailer,
					   lgh_primary_pup,
					   lgh_trailer3,
					   lgh_trailer4,
					   lgh_chassis,
					   lgh_chassis2,
					   lgh_dolly,
					   lgh_dolly2,
					   trl_company,
					   trl_fleet,
					   trl_division,
					   trl_terminal,
					   trl_type1,
					   trl_type2,
					   trl_type3,
					   trl_type4,
					   lgh_carrier,
					   lgh_createdby,
					   lgh_createdon,
					   lgh_createapp,
					   lgh_updatedby,
					   lgh_updatedon,
					   lgh_updateapp,
					   lgh_odometerstart,
					   lgh_odometerend,
					   cmp_id_rstart,
					   lgh_rstartcty_nmstct,
					   lgh_rstartcity,
					   lgh_rstartlat,
					   lgh_rstartlong,
					   stp_number_rstart,
					   lgh_rstartstate,
					   lgh_rstartdate,
					   lgh_rstartregion1,
					   lgh_rstartregion2,
					   lgh_rstartregion3,
					   lgh_rstartregion4,
					   cmp_id_rend,
					   lgh_rendcty_nmstct,
					   lgh_rendcity,
					   lgh_rendlat,
					   lgh_rendlong,
					   stp_number_rend,
					   lgh_rendstate,
					   lgh_renddate,
					   lgh_rendregion1,
					   lgh_rendregion2,
					   lgh_rendregion3,
					   lgh_rendregion4,
					   lgh_miles,
					   lgh_reftype,
					   lgh_refnum,
					   lgh_linehaul,
					   lgh_ord_charge,
					   lgh_act_weight,
					   lgh_est_weight,
					   lgh_tot_weight,
					   lgh_route,
					   lgh_direct_route_status1,
					   lgh_booked_revtype1,
					   lgh_204validate,
					   lgh_split_flag,
					   lgh_hzd_cmd_class,
					   lgh_prev_seg_status,
					   lgh_prev_seg_status_last_updated,
					   lgh_plannedhours,
					   lgh_raildispatchstatus
				FROM @lghTable
				WHERE crud_type = 'C';
	END

	IF EXISTS	(	SELECT	*
					FROM	@lghTable 
					WHERE	crud_type = 'U'
				) BEGIN

		 UPDATE LGH
		   SET
			   LGH.ord_hdrnumber = LghTable.ord_hdrnumber,
			   LGH.lgh_priority = LghTable.lgh_priority,
			   LGH.lgh_schdtearliest = LghTable.lgh_schdtearliest,
			   LGH.lgh_schdtlatest = LghTable.lgh_schdtlatest,
			   LGH.cmd_code = LghTable.cmd_code,
			   LGH.fgt_description = LghTable.fgt_description,
			   LGH.lgh_outstatus = LghTable.lgh_outstatus,
			   LGH.lgh_instatus = LghTable.lgh_instatus,
			   LGH.lgh_fueltaxstatus = LghTable.lgh_fueltaxstatus,
			   LGH.lgh_active = LghTable.lgh_active,
			   LGH.lgh_class1 = LghTable.lgh_class1,
			   LGH.lgh_class2 = LghTable.lgh_class2,
			   LGH.lgh_class3 = LghTable.lgh_class3,
			   LGH.lgh_class4 = LghTable.lgh_class4,
			   LGH.lgh_type1 = LghTable.lgh_type1,
			   LGH.lgh_type2 = LghTable.lgh_type2,
			   LGH.lgh_type3 = LghTable.lgh_type3,
			   LGH.lgh_type4 = LghTable.lgh_type4,
			   LGH.lgh_type5 = LghTable.lgh_type5,
			   LGH.cmp_id_start = LghTable.cmp_id_start,
			   LGH.lgh_startcty_nmstct = LghTable.lgh_startcty_nmstct,
			   LGH.lgh_startcity = LghTable.lgh_startcity,
			   LGH.lgh_originzip = LghTable.lgh_originzip,
			   LGH.lgh_startlat = LghTable.lgh_startlat,
			   LGH.lgh_startlong = LghTable.lgh_startlong,
			   LGH.stp_number_start = LghTable.stp_number_start,
			   LGH.lgh_startstate = LghTable.lgh_startstate,
			   LGH.lgh_startdate = LghTable.lgh_startdate,
			   LGH.lgh_startregion1 = LghTable.lgh_startregion1,
			   LGH.lgh_startregion2 = LghTable.lgh_startregion2,
			   LGH.lgh_startregion3 = LghTable.lgh_startregion3,
			   LGH.lgh_startregion4 = LghTable.lgh_startregion4,
			   LGH.cmp_id_end = LghTable.cmp_id_end,
			   LGH.lgh_endcty_nmstct = LghTable.lgh_endcty_nmstct,
			   LGH.lgh_endcity = LghTable.lgh_endcity,
			   LGH.lgh_destzip = LghTable.lgh_destzip,
			   LGH.lgh_endlat = LghTable.lgh_endlat,
			   LGH.lgh_endlong = LghTable.lgh_endlong,
			   LGH.stp_number_end = LghTable.stp_number_end,
			   LGH.lgh_endstate = LghTable.lgh_endstate,
			   LGH.lgh_enddate = LghTable.lgh_enddate,
			   LGH.lgh_enddate_arrival = LghTable.lgh_enddate_arrival,
			   LGH.lgh_endregion1 = LghTable.lgh_endregion1,
			   LGH.lgh_endregion2 = LghTable.lgh_endregion2,
			   LGH.lgh_endregion3 = LghTable.lgh_endregion3,
			   LGH.lgh_endregion4 = LghTable.lgh_endregion4,
			   LGH.lgh_driver1 = LghTable.lgh_driver1,
			   LGH.lgh_driver2 = LghTable.lgh_driver2,
			   LGH.mpp_teamleader = LghTable.mpp_teamleader,
			   LGH.mpp_fleet = LghTable.mpp_fleet,
			   LGH.mpp_division = LghTable.mpp_division,
			   LGH.mpp_domicile = LghTable.mpp_domicile,
			   LGH.mpp_company = LghTable.mpp_company,
			   LGH.mpp_terminal = LghTable.mpp_terminal,
			   LGH.mpp_type1 = LghTable.mpp_type1,
			   LGH.mpp_type2 = LghTable.mpp_type2,
			   LGH.mpp_type3 = LghTable.mpp_type3,
			   LGH.mpp_type4 = LghTable.mpp_type4,
			   LGH.mpp2_type1 = LghTable.mpp2_type1,
			   LGH.mpp2_type2 = LghTable.mpp2_type2,
			   LGH.mpp2_type3 = LghTable.mpp2_type3,
			   LGH.mpp2_type4 = LghTable.mpp2_type4,
			   LGH.lgh_tractor = LghTable.lgh_tractor,
			   LGH.trc_company = LghTable.trc_company,
			   LGH.trc_division = LghTable.trc_division,
			   LGH.trc_teamleader = LghTable.trc_teamleader,
			   LGH.trc_fleet = LghTable.trc_fleet,
			   LGH.trc_terminal = LghTable.trc_terminal,
			   LGH.trc_type1 = LghTable.trc_type1,
			   LGH.trc_type2 = LghTable.trc_type2,
			   LGH.trc_type3 = LghTable.trc_type3,
			   LGH.trc_type4 = LghTable.trc_type4,
			   LGH.lgh_primary_trailer = LghTable.lgh_primary_trailer,
			   LGH.lgh_primary_pup = LghTable.lgh_primary_pup,
			   LGH.lgh_trailer3 = LghTable.lgh_trailer3,
			   LGH.lgh_trailer4 = LghTable.lgh_trailer4,
			   LGH.lgh_chassis = LghTable.lgh_chassis,
			   LGH.lgh_chassis2 = LghTable.lgh_chassis2,
			   LGH.lgh_dolly = LghTable.lgh_dolly,
			   LGH.lgh_dolly2 = LghTable.lgh_dolly2,
			   LGH.trl_company = LghTable.trl_company,
			   LGH.trl_fleet = LghTable.trl_fleet,
			   LGH.trl_division = LghTable.trl_division,
			   LGH.trl_terminal = LghTable.trl_terminal,
			   LGH.trl_type1 = LghTable.trl_type1,
			   LGH.trl_type2 = LghTable.trl_type2,
			   LGH.trl_type3 = LghTable.trl_type3,
			   LGH.trl_type4 = LghTable.trl_type4,
			   LGH.lgh_carrier = LghTable.lgh_carrier,
			   LGH.lgh_createdby = LghTable.lgh_createdby,
			   LGH.lgh_createdon = LghTable.lgh_createdon,
			   LGH.lgh_createapp = LghTable.lgh_createapp,
			   LGH.lgh_updatedby = LghTable.lgh_updatedby,
			   LGH.lgh_updatedon = LghTable.lgh_updatedon,
			   LGH.lgh_updateapp = LghTable.lgh_updateapp,
			   LGH.lgh_odometerstart = LghTable.lgh_odometerstart,
			   LGH.lgh_odometerend = LghTable.lgh_odometerend,
			   LGH.cmp_id_rstart = LghTable.cmp_id_rstart,
			   LGH.lgh_rstartcty_nmstct = LghTable.lgh_rstartcty_nmstct,
			   LGH.lgh_rstartcity = LghTable.lgh_rstartcity,
			   LGH.lgh_rstartlat = LghTable.lgh_rstartlat,
			   LGH.lgh_rstartlong = LghTable.lgh_rstartlong,
			   LGH.stp_number_rstart = LghTable.stp_number_rstart,
			   LGH.lgh_rstartstate = LghTable.lgh_rstartstate,
			   LGH.lgh_rstartdate = LghTable.lgh_rstartdate,
			   LGH.lgh_rstartregion1 = LghTable.lgh_rstartregion1,
			   LGH.lgh_rstartregion2 = LghTable.lgh_rstartregion2,
			   LGH.lgh_rstartregion3 = LghTable.lgh_rstartregion3,
			   LGH.lgh_rstartregion4 = LghTable.lgh_rstartregion4,
			   LGH.cmp_id_rend = LghTable.cmp_id_rend,
			   LGH.lgh_rendcty_nmstct = LghTable.lgh_rendcty_nmstct,
			   LGH.lgh_rendcity = LghTable.lgh_rendcity,
			   LGH.lgh_rendlat = LghTable.lgh_rendlat,
			   LGH.lgh_rendlong = LghTable.lgh_rendlong,
			   LGH.stp_number_rend = LghTable.stp_number_rend,
			   LGH.lgh_rendstate = LghTable.lgh_rendstate,
			   LGH.lgh_renddate = LghTable.lgh_renddate,
			   LGH.lgh_rendregion1 = LghTable.lgh_rendregion1,
			   LGH.lgh_rendregion2 = LghTable.lgh_rendregion2,
			   LGH.lgh_rendregion3 = LghTable.lgh_rendregion3,
			   LGH.lgh_rendregion4 = LghTable.lgh_rendregion4,
			   LGH.lgh_miles = LghTable.lgh_miles,
			   LGH.lgh_reftype = LghTable.lgh_reftype,
			   LGH.lgh_refnum = LghTable.lgh_refnum,
			   LGH.lgh_linehaul = LghTable.lgh_linehaul,
			   LGH.lgh_ord_charge = LghTable.lgh_ord_charge,
			   LGH.lgh_act_weight = LghTable.lgh_act_weight,
			   LGH.lgh_est_weight = LghTable.lgh_est_weight,
			   LGH.lgh_tot_weight = LghTable.lgh_tot_weight,
			   LGH.lgh_route = LghTable.lgh_route,
			   LGH.lgh_direct_route_status1 = LghTable.lgh_direct_route_status1,
			   LGH.lgh_booked_revtype1 = LghTable.lgh_booked_revtype1,
			   LGH.lgh_204validate = LghTable.lgh_204validate,
			   LGH.lgh_split_flag = LghTable.lgh_split_flag,
			   LGH.lgh_hzd_cmd_class = LghTable.lgh_hzd_cmd_class,
			   LGH.lgh_prev_seg_status = LghTable.lgh_prev_seg_status,
			   LGH.lgh_prev_seg_status_last_updated = LghTable.lgh_prev_seg_status_last_updated,
			   LGH.lgh_plannedhours = LghTable.lgh_plannedhours,
			   LGH.lgh_raildispatchstatus = LghTable.lgh_raildispatchstatus
		 FROM legheader LGH
			  INNER JOIN @lghTable LghTable ON LghTable.lgh_number = LGH.lgh_number
		 WHERE LghTable.crud_type = 'U';
	END

     INSERT INTO @Tractors
            SELECT lgh_tractor
            FROM legheader WITH (NOLOCK)
            WHERE mov_number = @mov
                  AND lgh_tractor <> 'UNKNOWN'
            UNION
            SELECT lgh_tractor
            FROM @lghTable
            WHERE lgh_tractor <> 'UNKNOWN';
     INSERT INTO @Drivers
            SELECT mpp_id
            FROM
            (
                SELECT lgh_driver1,
                       lgh_driver2
                FROM legheader WITH (NOLOCK)
                WHERE mov_number = @mov
            ) AS LegDrivers UNPIVOT(mpp_id FOR mpp_ids IN(lgh_driver1,
                                                          lgh_driver2)) Drivers
            WHERE mpp_id <> 'UNKNOWN'
            UNION
            SELECT mpp_id
            FROM
            (
                SELECT lgh_driver1,
                       lgh_driver2
                FROM @lghTable
                WHERE mov_number = @mov
            ) AS LegDrivers UNPIVOT(mpp_id FOR mpp_ids IN(lgh_driver1,
                                                          lgh_driver2)) Drivers
            WHERE mpp_id <> 'UNKNOWN';
     IF @ProcessOutbound204 = 'Y'
         BEGIN
             DECLARE lghTableCursor CURSOR LOCAL FAST_FORWARD
             FOR SELECT lgh_number,
                        lgh_carrier
                 FROM @lghTable l
			  inner join carrier c on l.lgh_carrier = c.car_id
                 WHERE crud_type = 'D'
                       AND lgh_carrier IS NOT NULL
                       AND lgh_carrier <> 'UNKNOWN'
                       AND lgh_204status IN('TND', 'TDA', 'TDR', 'TDC')
                 AND (lgh_204validate IS NULL
                      OR lgh_204validate = 1)
				   and c.car_204flag = 1
			  AND (c.car_204update is null or c.car_204update in ('ALL', 'CAN'))
                 ORDER BY lgh_number;
             OPEN lghTableCursor;
             FETCH NEXT FROM lghTableCursor INTO @lgh, @car_id;
             WHILE @@FETCH_STATUS = 0
                 BEGIN
                     EXECUTE create_outbound204_cancel
                            @lgh,
                            @car_id;
                     FETCH NEXT FROM lghTableCursor INTO @lgh, @car_id;
                 END;
             CLOSE lghTableCursor;
             DEALLOCATE lghTableCursor;
         END;

	IF EXISTS	(	SELECT	*
					FROM	@lghTable
					WHERE	crud_type = 'D'
				) BEGIN

		 DELETE legheader
		 WHERE lgh_number IN
		 (
			 SELECT lgh_number
			 FROM @lghTable
			 WHERE crud_type = 'D'
		 );
	END

     IF @AllowMasterAssignments <> 'Y'
         UPDATE EVT
           SET
               EVT.evt_driver1 = 'UNKNOWN',
               EVT.evt_driver2 = 'UNKNOWN',
               EVT.evt_tractor = 'UNKNOWN',
               EVT.evt_trailer1 = 'UNKNOWN',
               EVT.evt_trailer2 = 'UNKNOWN',
               EVT.evt_trailer3 = 'UNKNOWN',
               EVT.evt_trailer4 = 'UNKNOWN',
               EVT.evt_chassis = 'UNKNOWN',
               EVT.evt_chassis2 = 'UNKNOWN',
               EVT.evt_dolly = 'UNKNOWN',
               EVT.evt_dolly2 = 'UNKNOWN',
               EVT.evt_carrier = 'UNKNOWN'
         FROM event EVT
              INNER JOIN stops S WITH (NOLOCK) ON S.stp_number = EVT.stp_number
              INNER JOIN @lghTable LGH ON LGH.lgh_number = S.lgh_number
         WHERE LGH.crud_type = 'D'
               AND (EVT.evt_driver1 <> 'UNKNOWN'
                    OR EVT.evt_driver2 <> 'UNKNOWN'
                    OR EVT.evt_tractor <> 'UNKNOWN'
                    OR EVT.evt_trailer1 <> 'UNKNOWN'
                    OR EVT.evt_trailer2 <> 'UNKNOWN'
                    OR EVT.evt_trailer3 <> 'UNKNOWN'
                    OR EVT.evt_trailer4 <> 'UNKNOWN'
                    OR EVT.evt_chassis <> 'UNKNOWN'
                    OR EVT.evt_chassis2 <> 'UNKNOWN'
                    OR EVT.evt_dolly <> 'UNKNOWN'
                    OR EVT.evt_dolly2 <> 'UNKNOWN'
                    OR EVT.evt_carrier <> 'UNKNOWN');
     IF @TrackBranch = 'Y'
         BEGIN
             UPDATE OH
               SET
                   OH.ord_broker = LGH.lgh_booked_revtype1
             FROM orderheader OH WITH (NOLOCK)
                  INNER JOIN @lghTable LGH ON LGH.ord_hdrnumber = OH.ord_hdrnumber
             WHERE LGH.legsequence = 1
                   AND COALESCE(OH.ord_broker, '') <> ''
                   AND LGH.lgh_booked_revtype1 <> OH.ord_broker;
         END;
     IF @assetassignmnet = 'Y'
         EXECUTE dbo.update_assetassignment
                 @mov;
     SELECT @minTractor = MIN(trc_number)
     FROM @Tractors;
     WHILE COALESCE(@minTractor, '') <> ''
         BEGIN
             EXECUTE dbo.trc_expstatus
                     @minTractor;
             EXECUTE dbo.instatus
                     @minTractor;
             SELECT @minTractor = MIN(trc_number)
             FROM @Tractors
             WHERE trc_number > @minTractor;
         END;
     SELECT @minDriver = MIN(mpp_id)
     FROM @Drivers;
     WHILE COALESCE(@minDriver, '') <> ''
         BEGIN
             EXECUTE dbo.drv_expstatus
                     @minDriver;
             SELECT @minDriver = MIN(mpp_id)
             FROM @Drivers
             WHERE mpp_id > @minDriver;
         END;
     EXECUTE dbo.update_trlstatus
             @mov;
     IF @SoftPta = 'Y'
         BEGIN
             SELECT TOP 1 @lgh = lgh_number,
                          @tractor = lgh_tractor
             FROM @lghTable
             WHERE crud_type IN('C', 'U')
             ORDER BY lgh_number;
             WHILE COALESCE(@lgh, 0) > 0
                 BEGIN
                     EXECUTE dbo.LegPTAUpdate_sp
                             @lgh,
                             @tractor,
                             NULL,
                             NULL,
                             NULL;
                     SELECT @prevlgh = @lgh,
                            @lgh = NULL;
                     SELECT TOP 1 @lgh = lgh_number,
                                  @tractor = lgh_tractor
                     FROM @lghTable
                     WHERE crud_type IN('C', 'U')
                     AND lgh_number > @prevlgh
                     ORDER BY lgh_number;
                 END;
         END;
     EXECUTE dbo.Assign_Third_Party_Defaults_sp
             @mov;
     EXECUTE dbo.reset_loadrequirements_sp
             @mov;
     IF @CheckPermitRequirementsOnSave = 'Y'
         EXECUTE dbo.reset_permitrequirements_sp
                 @mov;
     EXECUTE dbo.checkfreightdetails
             @mov;
     IF @FixOrderSequences = 'Y'
         EXECUTE dbo.Fix_Order_Sequences
                 @mov;
     IF @EnhPltTrkng = 'Y'
         EXECUTE dbo.generate_pallet_tracking_sp
                 @mov;
     EXECUTE dbo.Fix_Order_Totals_For_Move_sp
             @mov;
     IF @FuelInterface = 'Y'
         EXECUTE dbo.fuel_transaction_queue
                 @mov;
     IF @TchRealTimeStatus = 'Y'
        OR @TchRealTimeTractor = 'Y'
        OR @TchRealTimeTrailer = 'Y'
        OR @TchRealTimeTrip = 'Y'
         EXECUTE dbo.tch_transaction_queue
                 @mov,
                 @TchRealTimeStatus,
                 @TchRealTimeTractor,
                 @TchRealTimeTrailer,
                 @TchRealTimeTrip;
     IF @OrderCustomDate = 'Y'
         BEGIN
             EXECUTE dbo.UpdateMoveProcessing_OrderCustomDate_sp
                     @mov,
                     @CustomDateOrigin,
                     @CustomDateSource;
         END;
     IF EXISTS
     (
         SELECT 1
         FROM @stpTable
         WHERE stp_ico_stp_number_parent > 0
     )
         EXECUTE dbo.intercompany_ico_sync_child_to_parent_sp
                 @mov;
     EXECUTE create_stoptrailerrecord
             @mov;

/***********************************************************
** DO NOT PUT ANY LOGIC BELOW UPDATE MOVE POST PROCESS
** ADD ANY NEW LOGIC ABOVE THIS COMMENT
************************************************************/

     IF @UpdateMovePostProcessing = 'Y'
         EXECUTE dbo.update_move_postprocessing
                 @mov;

/***********************************************************
** DO NOT PUT ANY LOGIC BELOW UPDATE MOVE POST PROCESS
************************************************************/

GO


