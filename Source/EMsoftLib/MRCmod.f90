! ###################################################################
! Copyright (c) 2013-2020, Marc De Graef Research Group/Carnegie Mellon University
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without modification, are 
! permitted provided that the following conditions are met:
!
!     - Redistributions of source code must retain the above copyright notice, this list 
!        of conditions and the following disclaimer.
!     - Redistributions in binary form must reproduce the above copyright notice, this 
!        list of conditions and the following disclaimer in the documentation and/or 
!        other materials provided with the distribution.
!     - The name of Marc De Graef may not be used to endorse or promote products 
!	derived from this software without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
! AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
! IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
! ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
! LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
! DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
! SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
! CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
! OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
! USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
! ###################################################################
!--------------------------------------------------------------------------
! EMsoft:MRCmod.f90
!--------------------------------------------------------------------------
!
! MODULE: MRCmod
!
!> @author Marc De Graef 
!
!> @brief general routines for .mrc formatted IO, originally written as part of MCAP project
!> with AFRL/UES C-875-170-001 (2013).
!
!> @details  This was taken from http://www.biochem.mpg.de/doc_tom/index.html using the
!> tom_mrcfeistack2emseries code, as well as  http://bio3d.colorado.edu/imod/doc/mrc_format.txt
!> We are going to assume an IMOD version of 2.6.20 or better.
!>
!> Routines were tested against IDL version of MRC reader; a file generated by this program can
!> be read successfully by the IDL code.  The files created by this module should be readable 
!> by such programs as IMOD, FIJI and CHIMERA
!
!----------------------------------------------------------------
!----------------------------------------------------------------
!----------------------------------------------------------------
! here is how to save a data volume to an mrc file:
!
! ! in the declaration section your routine add the following lines:
!
! use MRCmod
! use typedefs
!
! type(MRCstruct) :: MRCheader
! type(FEIstruct) :: FEIheaders(1024)
! real(kind=dbl),allocatable :: psum(:)
! real(kind=dbl),allocatable :: volume(:,:,:)  ! you'll need to fill this array with values ... 
! integer(kind=irg)  :: numx, numy, numz       ! set these to the size of the volume array
! character(fnlen) :: fname                    ! and this is the output filename
! 
! ! assume that the data is called "volume" and has dimensions numx x numy x numz
! !----------------------------------------------------------------
! ! define the relevant entries in the MRCheader structure (other entries are not important and 
! ! will be set to their default values)
! MRCheader%nx = numx
! MRCheader%ny = numy
! MRCheader%nz = numz
! MRCheader%mode = 2    ! for floating point output
! MRCheader%mx = numx
! MRCheader%my = numy
! MRCheader%mz = numz
! MRCheader%amin = minval(volume)
! MRCheader%amax = maxval(volume)
! MRCheader%amean = sum(volume)/float(numx)/float(numy)/float(numz)
! MRCheader%xlen = numx
! MRCheader%ylen = numy
! MRCheader%zlen = numz
! 
! !----------------------------------------------------------------
! ! fill the relevant entries in the FEIheaders; none of these values are 
! ! actually used, except for mean_int
! allocate(psum(numz))
! psum = sum(sum(volume,1),1)
! do i=1,numz
!   FEIheaders(i)%b_tilt = 0.0
!   FEIheaders(i)%defocus = 0.0
!   FEIheaders(i)%pixelsize = 1.0e-9
!   FEIheaders(i)%magnification = 1000.0
!   FEIheaders(i)%voltage = 0.0
!   FEIheaders(i)%mean_int = psum(i)/float(numx)/float(numy)
! end do
! 
! !----------------------------------------------------------------
! ! and finally write the file; first construct the filename (full path included)
! fname =  trim(pathname)//trim(mrcname)//'.mrc'
! call MRC_write_3Dvolume(MRCheader,FEIheaders,fname,numx,numy,numz,volume,verbose=.TRUE.) ! last parameter is optional
!----------------------------------------------------------------
!----------------------------------------------------------------
!----------------------------------------------------------------
!
!> @date 04/17/13  MDG 1.0 based on information provided by Mike Jackson
!> @date 07/06/13  MDG 1.1 converted output format to float instead of uint
!> @date 05/30/17  MDG 2.0 integrated code with EMsoft 3.2 beta library
!--------------------------------------------------------------------------
module MRCmod

use local

IMPLICIT NONE

! a few local variables needed to actually write the file with direct access mode
! [it is easier to define them as variables local to the entire module than to pass them on all the time]
private :: RecLength, Rekord, Rec_No, L, Unit_No, MRC_write_MRCheader, MRC_write_FEIheaders, MRC_Write_Byte_Into_Buffer, &
           MRC_Write_Word, MRC_Write_Short, MRC_Write_Real, MRC_Write_String

integer(kind=irg),parameter :: RecLength = 256  ! direct access record length
character(len=256)          :: Rekord           ! this is a sort of output buffer
integer(kind=irg)           :: Rec_No=0, L=0    ! record parameters
integer(kind=irg)           :: Unit_No=64       ! output unit number

public :: MRC_write_3Dvolume

contains

!--------------------------------------------------------------------------
!
! SUBROUTINE: MRC_write_3Dvolume
!
!> @author Marc De Graef, Consultant
!
!> @brief creates a .mrc file and writes the volume (i.e., data volume) to it.
!
!> @param MRCheader mrc header block
!> @param FEIheaders FEI headers block
!> @param mrcname  complete mrc filename, including path
!> @param numx, numy, numz volume dimensions
!> @param volume volume (double precision reals)
!> @param verbose (optional) print messages to screen
!
!> @date 04/17/13 MDG 1.0 based on information provided by Mike Jackson
!> @date 05/01/13 MDG 1.1 corrected error in writing of actual volume
!> @date 05/30/17 MDG 2.0 updated for use in EMsoft 
!--------------------------------------------------------------------------
recursive subroutine MRC_write_3Dvolume(MRCheader, FEIheaders, mrcname, numx, numy, numz, volume, verbose)
!DEC$ ATTRIBUTES DLLEXPORT :: MRC_write_3Dvolume

use local
use io
use typedefs

IMPLICIT NONE

type(MRCstruct),INTENT(INOUT) :: MRCheader
!f2py intent(in,out) ::  MRCheader
!f2py intent(in,out) ::  MRCheader
type(FEIstruct),INTENT(INOUT) :: FEIheaders(1024)
!f2py intent(in,out) ::  FEIheaders
!f2py intent(in,out) ::  FEIheaders
character(fnlen),INTENT(IN)   :: mrcname
integer(kind=irg),INTENT(IN)  :: numx
integer(kind=irg),INTENT(IN)  :: numy
integer(kind=irg),INTENT(IN)  :: numz
real(kind=dbl),INTENT(IN)     :: volume(numx,numy,numz)
logical,INTENT(IN),optional   :: verbose

integer(kind=irg)             :: slen, j, ix ,iy, ith
character(34)                 :: s = 'mrc file created by EMsoft library'
logical                       :: v

v = .FALSE.
if (PRESENT(verbose)) then 
  if (verbose.eqv..TRUE.) v = .TRUE.
end if

! first set a label to indicate the origin of this file
 MRCheader % nlabels = 1
 slen = 34
 do j=1,slen
   MRCheader % labels(j:j) = s(j:j) 
 end do

 Rec_No = 0
 L = 0
 
! first we need to write the headers
if (v.eqv..TRUE.) call Message('Writing volume to file '//trim(mrcname))

open(UNIT=Unit_No,file=trim(mrcname),access="DIRECT",action="WRITE", &
     STATUS='unknown',FORM="UNFORMATTED", RECL=RecLength)

call MRC_write_MRCheader(MRCheader)
call MRC_write_FEIheaders(FEIheaders)

! next, write the volume
do ith = 1, numz
  do iy = 1, numy
    do ix = 1, numx
      call MRC_Write_Real(sngl(volume(ix,iy,ith)),4)
    end do
  end do
end do

! make sure the last record is actually written to the file
L=len(Rekord)
call MRC_Write_Byte_Into_Buffer(char(0))
 
! close and save file
 close(20,status="KEEP")

end subroutine MRC_write_3Dvolume

!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_write_MRCheader
!
!> @author Marc De Graef, Carnegie Melon University
!
!> @brief write the MRC header to the file
! 
!> @date    4/17/13 MDG 1.0 original code, written for MCAP project
!--------------------------------------------------------------------------
subroutine MRC_write_MRCheader(MRCheader)

use local
use typedefs

IMPLICIT NONE

type(MRCstruct),INTENT(INOUT)  :: MRCheader
!f2py intent(in,out) ::  MRCheader

integer(kind=irg)			   :: i

! this is a simple direct dump of all the structure entries into the MRC buffer
 call MRC_Write_Word(MRCheader%nx,4)
 call MRC_Write_Word(MRCheader%ny,4)
 call MRC_Write_Word(MRCheader%nz,4)
 call MRC_Write_Word(MRCheader%mode,4)
 call MRC_Write_Word(MRCheader%nxstart,4)
 call MRC_Write_Word(MRCheader%nystart,4)
 call MRC_Write_Word(MRCheader%nzstart,4)
 call MRC_Write_Word(MRCheader%mx,4)
 call MRC_Write_Word(MRCheader%my,4)
 call MRC_Write_Word(MRCheader%mz,4)
 call MRC_Write_Real(MRCheader%xlen,4)
 call MRC_Write_Real(MRCheader%ylen,4)
 call MRC_Write_Real(MRCheader%zlen,4)
 call MRC_Write_Real(MRCheader%alpha,4)
 call MRC_Write_Real(MRCheader%beta,4)
 call MRC_Write_Real(MRCheader%gamma,4)
 call MRC_Write_Word(MRCheader%mapc,4)
 call MRC_Write_Word(MRCheader%mapr,4)
 call MRC_Write_Word(MRCheader%maps,4)
 call MRC_Write_Real(MRCheader%amin,4)
 call MRC_Write_Real(MRCheader%amax,4)
 call MRC_Write_Real(MRCheader%amean,4)
 call MRC_Write_Short(MRCheader%ispg,2)
 call MRC_Write_Short(MRCheader%nsymbt,2)
 call MRC_Write_Word(MRCheader%next,4)
 call MRC_Write_Short(MRCheader%creatid,2)
 call MRC_Write_String(MRCheader%extra_data,30)
 call MRC_Write_Short(MRCheader%numint,2)   ! remember that this entry was renamed from nint
 call MRC_Write_Short(MRCheader%nreal,2)
 call MRC_Write_String(MRCheader%extra_data_2,20)
 call MRC_Write_Word(MRCheader%imodStamp,4)
 call MRC_Write_Word(MRCheader%imodFlags,4)
 call MRC_Write_Short(MRCheader%idtype,2)
 call MRC_Write_Short(MRCheader%lens,2)
 call MRC_Write_Short(MRCheader%nd1,2)
 call MRC_Write_Short(MRCheader%nd2,2)
 call MRC_Write_Short(MRCheader%vd1,2)
 call MRC_Write_Short(MRCheader%vd2,2)
 do i=1,6
   call MRC_Write_Real(MRCheader%tiltangles(i),4)
 end do
 call MRC_Write_Real(MRCheader%xorg,4)
 call MRC_Write_Real(MRCheader%yorg,4)
 call MRC_Write_Real(MRCheader%zorg,4)
 call MRC_Write_String(MRCheader%cmap,4)
 call MRC_Write_String(MRCheader%stamp,4)
 call MRC_Write_Real(MRCheader%rms,4)
 call MRC_Write_Word(MRCheader%nlabels,4)
 call MRC_Write_String(MRCheader%labels,800)

end subroutine MRC_write_MRCheader

!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_write_FEIheaders
!
!> @author Marc De Graef, Carnegie Melon University
!
!> @brief write the FEIheaders to the file
! 
!> @date    4/17/13 MDG 1.0 original code, written for MCAP project
!--------------------------------------------------------------------------
subroutine MRC_write_FEIheaders(FEIheaders)

use local
use typedefs

IMPLICIT NONE

type(FEIstruct),INTENT(INOUT)  :: FEIheaders(1024)
!f2py intent(in,out) ::  FEIheaders

integer(kind=irg)			   :: i

do i=1,1024
 call MRC_Write_Real(FEIheaders(i)%a_tilt,4)
 call MRC_Write_Real(FEIheaders(i)%b_tilt,4)
 call MRC_Write_Real(FEIheaders(i)%x_stage,4)
 call MRC_Write_Real(FEIheaders(i)%y_stage,4)
 call MRC_Write_Real(FEIheaders(i)%z_stage,4)
 call MRC_Write_Real(FEIheaders(i)%x_shift,4)
 call MRC_Write_Real(FEIheaders(i)%y_shift,4)
 call MRC_Write_Real(FEIheaders(i)%defocus,4)
 call MRC_Write_Real(FEIheaders(i)%exp_time,4)
 call MRC_Write_Real(FEIheaders(i)%mean_int,4)
 call MRC_Write_Real(FEIheaders(i)%tiltaxis,4)
 call MRC_Write_Real(FEIheaders(i)%pixelsize,4)
 call MRC_Write_Real(FEIheaders(i)%magnification,4)
 call MRC_Write_Real(FEIheaders(i)%voltage,4)
 call MRC_Write_String(FEIheaders(i)%unused,72)
end do

end subroutine MRC_write_FEIheaders

!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_Write_Byte_Into_Buffer
!
!> @author R.A. Vowels /Marc De Graef, Carnegie Melon University
!
!> @brief write a single byte into a buffer and dump the
!               buffer to file if full
!
!> @param Bite single byte to be added to the buffer

!> @note Renamed 'Byte' to 'Bite' since Byte is an f90 reserved word  
! 
!> @date    ?/??/96 RAV 1.0 original
!> @date    4/17/13 MDG 2.0 commented and change of variable names
!--------------------------------------------------------------------------
subroutine MRC_Write_Byte_Into_Buffer(Bite)

IMPLICIT NONE

character(len=1),intent(IN)   :: Bite  !< byte variable

! increment byte counter
 L=L+1
 
! is record full ?
 if (L>len(Rekord)) then  ! yes it is, so write to file
  Rec_No = Rec_No + 1
  write (Unit_No,REC=Rec_No) Rekord
! reset entire record to zero
  Rekord(1:len(Rekord))=char(0)
  L = 1
 end if

! add byte to record
 Rekord(L:L) = Bite

end subroutine MRC_Write_Byte_Into_Buffer


!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_Write_Word
!
!> @author R.A. Vowels /Marc De Graef, Carnegie Melon University
!
!> @brief write a 4-byte word into the buffer
!
!> @param Word 4-byte word
!> @param Length length parameter
! 
!> @date    ?/??/96 RAV 1.0 original
!> @date    4/17/13 MDG 2.0 commented and change of variable names
!--------------------------------------------------------------------------
subroutine MRC_Write_Word(Word,Length)

use local

IMPLICIT NONE

integer(kind=irg),intent(IN)    :: Word   !< 4-byte word
integer(kind=irg),intent(IN)    :: Length !< length parameter

integer(kind=irg)               :: L_Word
integer(kind=irg)               :: j
character(len=1)                :: Ch

 L_Word = Word
 do j=1,Length
  Ch = char(iand(L_Word,255))
  call MRC_Write_Byte_Into_Buffer(Ch)
  L_Word = ishft(L_Word,-8)
 end do
 
end subroutine MRC_Write_Word


!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_Write_Short
!
!> @author R.A. Vowels /Marc De Graef, Carnegie Melon University
!
!> @brief write a 2-byte integer into the buffer
!
!> @param Word 2-byte integer
!> @param Length length parameter
!! 
!> @date    4/17/13 MDG 1.0 original code
!--------------------------------------------------------------------------
subroutine MRC_Write_Short(Word,Length)

use local

IMPLICIT NONE

integer(kind=ish),INTENT(IN)        :: Word   !< 2 byte integer
integer(kind=irg),intent(IN)        :: Length !< length parameter

integer(kind=irg)                   :: L_Word
integer(kind=irg)                   :: j
character(len=1)                    :: Ch

 L_Word = Word
 do j=1,Length
  Ch = char(iand(L_Word,255))
  call MRC_Write_Byte_Into_Buffer(Ch)
  L_Word = ishft(L_Word,-8)
 end do
 
end subroutine MRC_Write_Short

!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_Write_Real
!
!> @author R.A. Vowels /Marc De Graef, Carnegie Melon University
!
!> @brief write a 4-byte real into the buffer
!
!> @param RWord 4-byte real
!> @param Length length parameter
!! 
!> @date    ?/??/96 RAV 1.0 original
!> @date    4/17/13 MDG 2.0 commented and change of variable names
!--------------------------------------------------------------------------
subroutine MRC_Write_Real(RWord,Length)

use local

IMPLICIT NONE

real(kind=sgl),INTENT(IN)       :: RWord  !< 4 byte real
integer(kind=irg),intent(IN)    :: Length !< length parameter

integer(kind=irg)               :: L_Word
integer(kind=irg)               :: j
character(len=1)                :: Ch

 L_Word = transfer(RWord,0)
 do j=1,Length
  Ch = char(iand(L_Word,255))
  call MRC_Write_Byte_Into_Buffer(Ch)
  L_Word = ishft(L_Word,-8)
 end do
 
end subroutine MRC_Write_Real

!--------------------------------------------------------------------------
!
! SUBROUTINE:MRC_Write_String
!
!> @author Marc De Graef, Carnegie Melon University
!
!> @brief write a series of characters into the buffer
!
!> @param Str string
!> @param Length string length parameter
!
!> @date    4/17/13 MDG 1.0 original
!--------------------------------------------------------------------------
subroutine MRC_Write_String(Str,Length)

use local

IMPLICIT NONE

character(*),intent(IN)         :: Str      !< input string
integer(kind=irg),intent(IN)    :: Length   !< length parameter

integer(kind=irg)               :: j

 do j=1,Length
  call MRC_Write_Byte_Into_Buffer(Str(j:j))
 end do
 
end subroutine MRC_Write_String

end module MRCmod
