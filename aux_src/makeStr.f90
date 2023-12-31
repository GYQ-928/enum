! This program reads in a file in struct_enum.out format and writes out
! a VASP-like structure file for one of the structures.
PROGRAM makeStr
use num_types
use vector_matrix_utilities
use numerical_utilities
use enumeration_utilities ! This maps structures from real space into the group
use enumeration_types, only: maxLabLength
use io_utils, only: co_ca
implicit none
character(80) fname, title, strname, strNstring
character(maxLabLength) :: labeling
integer ioerr, iline, ic, i, ilab, pgOps, nD, hnfN, iAt, jAt, nSpec, idx, foutput_unit
integer k, strN, istrN, strNi, strNf, sizeN, n, diag(3), a,b,c,d,e,f, nType
integer HNF(3,3), L(3,3), hnf_degen, lab_degen, tot_degen
integer, pointer :: gIndx(:)
real(dp) :: p(3,3), sLV(3,3), eps, Ainv(3,3), sLVinv(3,3), shift(3) ! Parent lattice
real(dp), pointer :: aBas(:,:), dvec(:,:) ! pointer so it can be passed in to a routine; aBas is the list of atomic basis vectors
integer, pointer :: nSpecType(:) 
character(1) bulksurf
character(80) dummy, specAtoms 
integer, pointer :: spin(:) ! Occupation variable of the positions
real(dp), pointer :: x(:) ! Concentration of each component
logical :: file_exists, co_ca_error

open(13,file="readcheck_makestr.out")
write(13,'(5(/),"This file echoes the input for the makestr.x program and")')
write(13,'("prints some of the computed quantities as well. It is intended to")')
write(13,'("be useful for debugging and fixing bad input")')
write(13,'("***************************************************")')

if(iargc()/=2 .and. (iargc()/=3 .and. iargc()/=4)) stop "makestr.x requires two (optional three or four)  arguments: &
               & the filename to read from and the number of the structure (to start and to stop at)"
call getarg(1,dummy)
read(dummy,'(a80)') fname
call getarg(2,dummy)
read(dummy,*) strNi
if (iargc()>=3) then
  call getarg(3,dummy)
  read(dummy,*) strNf
else
  strNf=strNi
endif
if (iargc()==4) then
  call getarg(4, dummy)
  read(dummy, *) foutput_unit
else
  foutput_unit = 12
endif

! Modifications made by GLWH 03/05/2014.
!
! If the parent cell for a cluster expansion contains "spectator
! atoms" (sites where the same atom always appears---no
! configurational degrees of freedom) then we need to add these to the
! poscar files (but as the code is written now, spectators are not
! explicitly included in the CE input and output). The short-term
! workaround (watch it last for years. Argh) is to add the spectators
! by hand using a "spectators.in" file. 

! This file contains on line 1 a list of how many atoms (spectators
! only) of each type are in the file (just like line 6 in the poscar
! file). Each line after that lists the position of the spectator
! atoms (in direct coordinates!) in blocks of the same type
! (consistent with line 1 of the file).
nSpec = 0
nType = 0

inquire(file="spectators.in", exist=file_exists)
if (file_exists) then ! figure out how many spectators there are
   open(14,file="spectators.in",action="read")
   read(14,'(a80)') specAtoms
   dummy = specAtoms
   do
      read(dummy,*) iAt
      nSpec = iAt + nSpec
      dummy = adjustl(dummy(index(dummy," "):)) ! Throw away the number we just read in
      nType = nType + 1
      if (dummy == "") exit
   end do
   write(13,'("Number of types of spectators:",i3)') nType
   ! Now figure out how many of each type there are
   allocate(nSpecType(nType))
   dummy = specAtoms
   do iAt = 1, nType
      read(dummy,*) jAt
      nSpecType(iAt) = jAt
      dummy = adjustl(dummy(index(dummy," "):)) ! Throw away the number we just read in
      write(13,'("Number of spectators of type ",i2,":",i3)')iAt,jAt
   end do
end if
! **** End modification ****

!call read_nth_line_from_enumlist()
open(11,file=fname,status='old',iostat=ioerr)
if(ioerr/=0)then; write(*,'("Input file doesn''t exist:",a80)') trim(fname);stop;endif
call co_ca(11, co_ca_error)
! Read in the title from the struct_enum.out file
read(11,'(a80)') title; title = trim(title)
write(13,'("Title: ",a80)') title

! Read in surf/bulk mode marker
read(11,'(a1)') bulksurf
write(13,'("bulk/surf: ",a1)') bulksurf

! Read in the parent lattice vectors
do i = 1,3; read(11,*) p(:,i); enddo
call matrix_inverse(p,Ainv)
write(13,'("Parent lattice:",/,3(3f7.3,1x,/))') (p(:,i),i=1,3) 
write(13,'("Parent lattice inverse matrix:",/,3(3f7.3,1x,/))') (Ainv(:,i),i=1,3) 

! Read in the number of d-vectors, then read each one in
read(11,*) nD
!!GH Updated to handle spectators
!!GH allocate(dvec(3,nD))
allocate(dvec(3,nD+nSpec))
do i = 1,nD; read(11,*) dvec(:,i); enddo
write(13,'("d-vectors:",/,40(3f8.4,1x,/))') (dvec(:,i),i=1,nD) 
!!GH Now read in the spectators. Like the normal dvectors read in from
!!the enumeration file, the spectator atoms should be in *Cartesian*
!!coordinates. 
do i = nD + 1, nD + nSpec
   read(14,*) shift
   if (all(shift < 1.0_dp .and. shift > 0._dp)) write(*,'( "WARNING: In the ''spectators.in'' file, coordinates should be in Cartesian coordinates")')
   dvec(:,i) = shift
enddo
write(13,'("Spectators:",/,40(3f8.4,1x,/))') (dvec(:,i+nD),i=1,nSpec) 

! Read in the number of labels, i.e., binary, ternary, etc.
read(11,'(i2)') k
!!GH generalize for spectators
k = k + nType
write(13,'("Number of labels (k): ",i2)') k 
read(11,*)
read(11,*) eps
write(13,'("Finite precision parameter (epsilon): ",g17.10)') eps 

do 
   read(11,*) dummy
   if(dummy=="start") exit
enddo
write(13,'("Found ""start"" label. Now skipping lines to struct #: ",i10)') strNi 

! Skip to the specified structure number
do iline = 1, strNi-1
   read(11,*)! dummy; print *,dummy
enddo
write(13,'("Skipped to the ",i10,"-nth line in ",a80)') strNi,fname 

! Read in the info for the given structure
do istrN=strNi,strNf
   read(11,*) strN, hnfN, hnf_degen, lab_degen, tot_degen,sizeN, n, pgOps, diag, a,b,c,d,e,f, L, labeling
   write(13,'("strN, hnfN, sizeN, n, pgOps, diag, a,b,c,d,e,f, L, labeling")')  
   write(13,'(i11,1x,i7,1x,i8,1x,i2,1x,i2,1x,3(i3,1x),1x,6(i3,1x),1x,9(i3,1x),1x,a40)') &
        strN, hnfN, sizeN, n, pgOps, diag, a,b,c,d,e,f, L, labeling
   ! Add the spectator atoms to the labeling
   idx = n*nD ! Index keeps track of where we are in the labeling
   do i = 1, n ! Loop over the number of parent cells in the supercell
      do iAt = 1, nType ! Loop over the number of types of spectators
         do jAt = 1, nSpecType(iAt) ! Loop over the number of this type
            idx = idx + 1
            print *, jAt,"jAt"
            print *,nSpecType(iAt),"nspectype"
            labeling(idx:idx) = char(iAt + k - nType - 1 + 48)
         enddo
      end do
   end do
   write(13,'("New labeling with spectators added: ",a40)') labeling
   L = transpose(L) ! Listed with columns as the fast index in the struct_enum.out but reads
                    ! in with rows as the fast index. This was the source of a hard-to-find bug
   ! Define the full HNF matrix
   HNF = 0
   HNF(1,1) = a; HNF(2,1) = b; HNF(2,2) = c
   HNF(3,1) = d; HNF(3,2) = e; HNF(3,3) = f
   write(13,'("HNF from file",6(1x,i3),//)') a,b,c,d,e,f

   call map_enumStr_to_real_space(k,n,HNF,labeling,p,dvec,eps,sLV,aBas,spin,gIndx,x,L,diag,minkowskiReduce=.true.)
   write(strname,'("vasp.",i6.6)') strN
   write(strNstring,*) strN
   if (foutput_unit /= 6) then
      open(foutput_unit, file=strname)
   endif
   write(foutput_unit,'(a80)') trim(adjustl(title)) // " str #: " // adjustl(strNstring)
   !GH write(foutput_unit,'("scale factor")')
   write(foutput_unit,'("1.00")')
   do i = 1,3
      write(foutput_unit,'(3(f12.8,1x))') sLV(:,i)
   enddo
   call matrix_inverse(sLV,sLVinv)
   write(13,'("New inverse after reduction",/,3(3(f7.3,1x),/))') (sLVinv(i,:),i=1,3) 
   
   ! This part counts the number of atoms of each type and lists the numbers on the line before the atomic basis vectors
   do i = 0, k-1
      ic = 0
      do iAt = 1, n*(nD+nSpec)
         if (labeling(gIndx(iAt):gIndx(iAt))==char(i+48)) then
            ic = ic + 1
            write(13,'("Atom #: ",i2," given label #",i2," label: ",a1)') iAt, ic,labeling(gIndx(iAt):gIndx(iAt))
         endif
      enddo
      write(foutput_unit,'(i3,1x)',advance='no') ic
      write(13,'(i3," atoms of label type ",i2," found")') ic, i
   enddo
   write(13,'("Finished counting the atoms of each type")')  
   ! Write the number of spectator atoms on line 6 of the poscar
   !if (file_exists) write(12,'(100(i4,1x))',advance="no") nSpecType*n
   write(foutput_unit,'(/,"D")')
   
   ! This part lists the atomic basis vectors that we found in the triple z1, z2, z3 loops above.
   ! For vasp, UNCLE it needs to list the vectors in blocks of atoms that have the same label.
   call cartesian2direct(sLV,aBas,eps)
   do ilab = 0,k-1
      do iAt = 1, n*(nD+nSpec)
         if (labeling(gIndx(iAt):gIndx(iAt))==char(ilab+48)) then ! We have a match to the current
            ! label so print it
           write(foutput_unit,'(3(f12.8,1x))') aBas(:,iAt)
           write(13,'("At. #: ",i2," position:",3(f7.3,1x),"<",a1,">")') iAt, aBas(:,iAt), labeling(gIndx(iAt):gIndx(iAt))
         endif
      enddo
   enddo

!!GH! **** Spectators part ****
!!GH! Now, if there are spectators in the parent cell, put them in the superlattice POSCAR
!!GH   if(file_exists) then
!!GH      do iSpec = 1, nType
!!GH         do jAt = 1, nSpecType(iSpec)
!!GH            read(14,*) shift
!!GH            if (any(shift >= 1.0_dp)) stop "ERROR: In the 'spectators.in' file, coordinates should be direct coordinates"
!!GH            do iAt = 1, n               
!!GH!                write(foutput_unit,'(3(f12.8,1x),"spectator type:",i2,1x," cell#",i4)')&
!!GH!                    & aBas(:,iAt) + shift, iSpec, iAt
!!GH               write(foutput_unit,'(3(f12.8,1x))') fraction(aBas(:,iAt) + shift)
!!GH               write(13,'("At. #: ",i2," position:",3(f7.3,1x),"<",a1,"&
!!GH                    &>",3x,"Cell #",i3,2x,"Type ",i2)') iAt, aBas(:&
!!GH                    &,iAt), labeling(gIndx(iAt):gIndx(iAt)), iAt, iSpec
!!GH            end do
!!GH            !rewind(14)
!!GH            !read(14,*)
!!GH         end do
!!GH      end do
!!GH      close(14)
!!GH   end if

   close(foutput_unit);
   deallocate(spin,x,gIndx,aBas)
enddo ! structure loop
if (file_exists) close(14)
close(11)
close(13)
END PROGRAM makeStr
