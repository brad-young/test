USE [TMW_Live]
GO

/****** Object:  StoredProcedure [dbo].[Update_move_postprocessing_Market]    Script Date: 1/20/2025 9:36:30 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



ALTER Procedure [dbo].[Update_move_postprocessing_Market] (@mov int) AS

Declare @cmp varchar (8)
Select @cmp = Count(ord_shipper) from orderheader 
Where ord_shipper <> 'UNKNOWN' and ord_extrainfo14 is NULL

Begin
If @cmp > 0 
Begin
Update O
Set O.ord_extrainfo14 = (Select name from labelfile where labeldefinition = 'RevType1' and abbr = C.cmp_revtype1)
From orderheader O
Join company C on c.cmp_id = O.ord_shipper and
O.mov_number = @mov
End
END
GO


