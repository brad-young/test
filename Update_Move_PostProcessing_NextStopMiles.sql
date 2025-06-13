USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[Update_Move_PostProcessing_NextStopMiles]    Script Date: 1/20/2025 9:37:13 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO







ALTER Procedure [dbo].[Update_Move_PostProcessing_NextStopMiles] (@mov int)
as
Begin

CREATE table #leg 
(lgh_number int,
lgh_extrainfo1 varchar (30),
mov_number int,
lgh_driver1 varchar (8),
lgh_outstatus varchar(6));


Insert into #leg (lgh_number, lgh_extrainfo1, mov_number, lgh_driver1, lgh_outstatus)
Select lgh_number, ISNull(lgh_extrainfo1,0), mov_number, ISNull(lgh_driver1,'UNKNOWN'), lgh_outstatus
from legheader
where lgh_outstatus = 'STD' and mov_number = @mov;


/***** First check to see if the value has already been set ****/
--If exists (Select 1 from #leg)
--Begin
--Return
--End

/**** Second check to see if the value needs to be set ****/
--ELSE
Begin
Update l
Set l.lgh_extrainfo1 = 
(

Select Top 1 Concat ('Miles between - ',CAST([dbo].[fnc_AirMilesBetweenCityCodes]((c1.cty_code),c2.cty_code) as decimal(5,1))) 
From checkcall cc
Left Join stops s on s.lgh_number = cc.ckc_lghnumber
Inner Join city c1 on c1.cty_code = s.stp_city and s.stp_city = (Select Top 1 stp_city from stops where stp_status = 'OPN' and lgh_number = cc.ckc_lghnumber order by stp_arrivaldate)
Inner Join city c2 on c2.cty_code = cc.ckc_city
Left Join legheader l on l.lgh_number = cc.ckc_lghnumber
Where l.lgh_outstatus = 'STD' and cc.ckc_lghnumber = s.lgh_number and l.mov_number = @mov
order by cc.ckc_updatedon DESC

--Select Top 1 Concat ('Miles between - ',CAST([dbo].[fnc_AirMilesBetweenCityCodes]((c1.cty_code),c2.cty_code) as decimal(5,1))) 
--From checkcall cc
--Left Join stops s on s.lgh_number = cc.ckc_lghnumber
--Inner Join city c1 on c1.cty_code = s.stp_city and s.stp_city = (Select Top 1 stp_city from stops where stp_status = 'OPN' and lgh_number = cc.ckc_lghnumber order by stp_arrivaldate)
--Inner Join city c2 on c2.cty_code =  (Select Top 1 ckc_city from checkcall where ckc_lghnumber = s.lgh_number order by ckc_updatedon DESC)
--Left Join legheader l on l.lgh_number = cc.ckc_lghnumber
--Where l.lgh_outstatus = 'STD' and l.mov_number = 1551679
--order by cc.ckc_updatedon DESC
)
from legheader l
Where l.mov_number = @mov
end
END

DROP TABLE #leg

GO


