module DMFT_GK
  USE SF_CONSTANTS, only: one,xi,zero,pi
  USE SF_LINALG,    only: eye,inv,inv_sym,inv_tridiag,get_tridiag
  USE SF_ARRAYS,    only: linspace,arange
  USE SF_MISC,      only: assert_shape
  USE DMFT_CTRL_VARS
#ifdef _MPI
  USE MPI
#endif
  implicit none
  private


  interface dmft_gk_matsubara
     module procedure :: dmft_get_gk_matsubara_normal_main
     module procedure :: dmft_get_gk_matsubara_normal_dos
     module procedure :: dmft_get_gk_matsubara_normal_ineq
     module procedure :: dmft_get_gk_matsubara_superc_main
     module procedure :: dmft_get_gk_matsubara_superc_dos
     module procedure :: dmft_get_gk_matsubara_superc_ineq
#ifdef _MPI
     module procedure :: dmft_get_gk_matsubara_normal_main_mpi
     module procedure :: dmft_get_gk_matsubara_normal_dos_mpi
     module procedure :: dmft_get_gk_matsubara_normal_ineq_mpi
     module procedure :: dmft_get_gk_matsubara_superc_main_mpi
     module procedure :: dmft_get_gk_matsubara_superc_dos_mpi
     module procedure :: dmft_get_gk_matsubara_superc_ineq_mpi     
#endif
  end interface dmft_gk_matsubara



  interface dmft_gk_realaxis
     module procedure :: dmft_get_gk_realaxis_normal_main
     module procedure :: dmft_get_gk_realaxis_normal_dos
     module procedure :: dmft_get_gk_realaxis_normal_ineq
     module procedure :: dmft_get_gk_realaxis_superc_main
     module procedure :: dmft_get_gk_realaxis_superc_dos
     module procedure :: dmft_get_gk_realaxis_superc_ineq
#ifdef _MPI
     module procedure :: dmft_get_gk_realaxis_normal_main_mpi
     module procedure :: dmft_get_gk_realaxis_normal_dos_mpi
     module procedure :: dmft_get_gk_realaxis_normal_ineq_mpi
     module procedure :: dmft_get_gk_realaxis_superc_main_mpi
     module procedure :: dmft_get_gk_realaxis_superc_dos_mpi
     module procedure :: dmft_get_gk_realaxis_superc_ineq_mpi
#endif
  end interface dmft_gk_realaxis



  !PUBLIC IN DMFT:
  public :: dmft_gk_matsubara
  public :: dmft_gk_realaxis



  !####################################################################
  !                    COMPUTATIONAL ROUTINES
  !####################################################################
  interface select_block
     module procedure :: select_block_Nlso
     module procedure :: select_block_nnn
  end interface select_block
  interface lso2nnn_reshape
     module procedure d_nlso2nnn
     module procedure c_nlso2nnn
  end interface lso2nnn_reshape
  interface so2nn_reshape
     module procedure d_nso2nn
     module procedure c_nso2nn
  end interface so2nn_reshape
  interface nnn2lso_reshape
     module procedure d_nnn2nlso
     module procedure c_nnn2nlso
  end interface nnn2lso_reshape
  interface nn2so_reshape
     module procedure d_nn2nso
     module procedure c_nn2nso
  end interface nn2so_reshape


  real(8),dimension(:),allocatable          :: wm !Matsubara frequencies
  real(8),dimension(:),allocatable          :: wr !Real frequencies
  integer                                   :: Lk,Nlso,Nlat,Nspin,Norb,Nso,Lreal,Lmats
  integer                                   :: i,j,ik,ilat,jlat,iorb,jorb,ispin,jspin,io,jo,is,js
  !
  integer                                   :: mpi_ierr
  integer                                   :: mpi_rank
  integer                                   :: mpi_size
  logical                                   :: mpi_master
  !
  real(8)                                   :: beta
  real(8)                                   :: xmu,eps
  real(8)                                   :: wini,wfin 






  !####################################################################
  !####################################################################

contains


  !####################################################################
  !####################################################################

  include "dmft_gk_matsubara_normal.f90"
  include "dmft_gk_matsubara_superc.f90"
  include "dmft_gk_realaxis_normal.f90"
  include "dmft_gk_realaxis_superc.f90"
#ifdef _MPI
  include "dmft_gk_matsubara_normal_mpi.f90"
  include "dmft_gk_matsubara_superc_mpi.f90"
  include "dmft_gk_realaxis_normal_mpi.f90"
  include "dmft_gk_realaxis_superc_mpi.f90"
#endif






  !--------------------------------------------------------------------!
  ! PURPOSE: invert the Gk matrix in all cases:
  ! + normal/superc
  ! + serial/parallel
  ! + single site/tridiagonal/lattice/full gij
  !--------------------------------------------------------------------!
  !
  ! INVERT_GK_NORMAL(_MPI)
  !
  !SERIAL (OR PARALLEL ON K):
  subroutine invert_gk_normal(zeta,Hk,hk_symm,Gkout)
    complex(8),dimension(:,:,:),intent(in)        :: zeta    ![Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)          :: Hk      ![Nspin*Norb][Nspin*Norb]
    logical,intent(in)                            :: hk_symm                
    complex(8),dimension(:,:,:,:,:),intent(inout) :: Gkout   ![Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:),allocatable   :: Gktmp   ![Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable         :: Gmatrix ![Nspin*Norb][Nspin*Norb]
    integer                                       :: Nspin,Norb,Nso,Lfreq
    integer                                       :: i,iorb,jorb,ispin,jspin,io,jo
    !
    Nspin = size(Gkout,1)
    Norb  = size(Gkout,3)
    Lfreq = size(zeta,3)
    Nso   = Nspin*Norb
    !testing
    call assert_shape(zeta,[Nso,Nso,Lfreq],"invert_gk_normal","zeta")
    call assert_shape(Hk,[Nso,Nso],"invert_gk_normal","Hk")
    call assert_shape(Gkout,[Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal","Gkout")
    !
    allocate(Gktmp(Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nso,Nso))
    Gktmp=zero
    do i=1,Lfreq
       Gmatrix  = zeta(:,:,i) - Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   io = iorb + (ispin-1)*Norb
                   jo = jorb + (jspin-1)*Norb
                   Gktmp(ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout = Gktmp
  end subroutine invert_gk_normal

  !PARALLEL ON FREQ:
#ifdef _MPI
  subroutine invert_gk_normal_mpi(MpiComm,zeta,Hk,hk_symm,Gkout)
    integer                                       :: MpiComm
    complex(8),dimension(:,:,:),intent(in)        :: zeta    ![Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)          :: Hk      ![Nspin*Norb][Nspin*Norb]
    logical,intent(in)                            :: hk_symm                
    complex(8),dimension(:,:,:,:,:),intent(inout) :: Gkout   ![Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:),allocatable   :: Gktmp   ![Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable         :: Gmatrix ![Nspin*Norb][Nspin*Norb]
    integer                                       :: Nspin,Norb,Nso,Lfreq
    integer                                       :: i,iorb,jorb,ispin,jspin,io,jo
    !
    !
    !MPI setup:
    mpi_size  = MPI_Get_size(MpiComm)
    mpi_rank =  MPI_Get_rank(MpiComm)
    mpi_master= MPI_Get_master(MpiComm)
    !
    Nspin = size(Gkout,1)
    Norb  = size(Gkout,3)
    Lfreq = size(zeta,3)
    Nso   = Nspin*Norb
    !testing
    call assert_shape(zeta,[Nso,Nso,Lfreq],"invert_gk_normal_mpi","zeta")
    call assert_shape(Hk,[Nso,Nso],"invert_gk_normal_mpi","Hk")
    call assert_shape(Gkout,[Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal_mpi","Gkout")
    !
    allocate(Gktmp(Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nso,Nso))
    Gktmp=zero
    do i=1+mpi_rank,Lfreq,mpi_size
       Gmatrix  = zeta(:,:,i) - Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   io = iorb + (ispin-1)*Norb
                   jo = jorb + (jspin-1)*Norb
                   Gktmp(ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout=zero
    call MPI_AllReduce(Gktmp, Gkout, size(Gkout), MPI_Double_Complex, MPI_Sum, MpiComm, mpi_ierr)
  end subroutine invert_gk_normal_mpi
#endif







  !
  ! INVERT_GK_NORMAL_INEQ(_MPI)
  !
  !SERIAL (OR PARALLEL ON K)
  subroutine invert_gk_normal_ineq(zeta,Hk,hk_symm,Gkout)
    complex(8),dimension(:,:,:,:),intent(in)        :: zeta    ![Nlat][Nlat*Nspin*Norb][Nlat*Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)            :: Hk      ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                              :: hk_symm
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    !
    complex(8),dimension(:,:,:),allocatable         :: Gembed  ![Nlat*Nspin*Norb][Nlat*Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable           :: Gmatrix ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    integer                                         :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                         :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    Nlat  = size(zeta,1)
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,4)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    !Testing:
    call assert_shape(zeta,[Nlat,Nso,Nso,Lfreq],"invert_gk_normal_ineq","zeta")
    call assert_shape(Hk,[Nlso,Nlso],"invert_gk_normal_ineq","Hk")
    call assert_shape(Gkout,[Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal_ineq","Gkout")
    !
    allocate(Gktmp(Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nlso,Nlso))
    Gktmp=zero
    do i=1,Lfreq
       Gmatrix  = blocks_to_matrix(zeta(:,:,:,i),Nlat,Nso) - Hk
       if(allocated(Gembed))Gmatrix = Gmatrix - Gembed(:,:,i)
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                      jo = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                      Gktmp(ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout = Gktmp
  end subroutine invert_gk_normal_ineq

  !PARALLEL ON FREQ:
#ifdef _MPI
  subroutine invert_gk_normal_ineq_mpi(MpiComm,zeta,Hk,hk_symm,Gkout)
    integer                                         :: MpiComm
    complex(8),dimension(:,:,:,:),intent(in)        :: zeta    ![Nlat][Nlat*Nspin*Norb][Nlat*Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)            :: Hk      ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                              :: hk_symm
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    !
    complex(8),dimension(:,:,:),allocatable         :: Gembed  ![Nlat*Nspin*Norb][Nlat*Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable           :: Gmatrix ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    integer                                         :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                         :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    !MPI setup:
    mpi_size  = MPI_Get_size(MpiComm)
    mpi_rank =  MPI_Get_rank(MpiComm)
    mpi_master= MPI_Get_master(MpiComm)
    !
    Nlat  = size(zeta,1)
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,4)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    call assert_shape(zeta,[Nlat,Nso,Nso,Lfreq],"invert_gk_normal_ineq_mpi","zeta")
    call assert_shape(Hk,[Nlso,Nlso],"invert_gk_normal_ineq_mpi","Hk")
    call assert_shape(Gkout,[Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal_ineq_mpi","Gkout")
    !
    !
    allocate(Gktmp(Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nlso,Nlso))
    Gktmp=zero
    do i=1+mpi_rank,Lfreq,mpi_size
       Gmatrix  = blocks_to_matrix(zeta(:,:,:,i),Nlat,Nso) - Hk
       if(allocated(Gembed))Gmatrix = Gmatrix - Gembed(:,:,i)
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                      jo = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                      Gktmp(ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout=zero
    call MPI_AllReduce(Gktmp, Gkout, size(Gkout), MPI_Double_Complex, MPI_Sum, MpiComm, mpi_ierr)
  end subroutine invert_gk_normal_ineq_mpi
#endif












  !
  ! INVERT_GK_NORMAL_TRIDIAG(_MPI)
  !
  !SERIAL (OR PARALLEL ON K)
  subroutine invert_gk_normal_tridiag(zeta,Hk,hk_symm,Gkout)
    complex(8),dimension(:,:,:,:),intent(in)        :: zeta    ![Nlat][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)            :: Hk      ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                              :: hk_symm
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    !
    complex(8),dimension(:,:,:,:),allocatable       :: Gembed  ![Nlat][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:),allocatable         :: Diag
    complex(8),dimension(:,:,:),allocatable         :: Sub
    complex(8),dimension(:,:,:),allocatable         :: Over
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:),allocatable         :: Gmatrix ![Nlat][Nspin*Norb][Nspin*Norb]
    integer                                         :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                         :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    Nlat  = size(zeta,1)
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,4)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    !Testing
    call assert_shape(zeta,[Nlat,Nso,Nso,Lfreq],"invert_gk_normal_tridiag","zeta")
    call assert_shape(Hk,[Nlso,Nlso],"invert_gk_normal_tridiag","Hk")
    call assert_shape(Gkout,[Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal_tridiag","Gkout")
    !
    !
    allocate(Sub(Nlat-1,Nso,Nso))
    allocate(Diag(Nlat,Nso,Nso))
    allocate(Over(Nlat-1,Nso,Nso))
    allocate(Gktmp(Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nlat,Nso,Nso))
    Gktmp=zero
    do i=1,Lfreq
       call get_tridiag(Nlat,Nso,Hk,Sub,Diag,Over)
       Diag = zeta(:,:,:,i) - Diag
       if(allocated(Gembed))Diag = Diag - Gembed(:,:,:,i)
       call inv_tridiag(Nlat,Nso,-Sub,Diag,-Over,Gmatrix)
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb
                      jo = jorb + (jspin-1)*Norb
                      Gktmp(ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(ilat,io,jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout = Gktmp
  end subroutine invert_gk_normal_tridiag

  !PARALLEL ON FREQ:
#ifdef _MPI
  subroutine invert_gk_normal_tridiag_mpi(MpiComm,zeta,Hk,hk_symm,Gkout)
    integer                                         :: MpiComm
    complex(8),dimension(:,:,:,:),intent(in)        :: zeta    ![Nlat][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:),intent(in)            :: Hk      ![Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                              :: hk_symm
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    !
    complex(8),dimension(:,:,:),allocatable         :: Diag
    complex(8),dimension(:,:,:),allocatable         :: Sub
    complex(8),dimension(:,:,:),allocatable         :: Over
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:),allocatable         :: Gmatrix ![Nlat][Nspin*Norb][Nspin*Norb]
    complex(8),dimension(:,:,:,:),allocatable       :: Gembed  ![Nlat][Nspin*Norb][Nspin*Norb][Lfreq]    
    integer                                         :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                         :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    !MPI setup:
    mpi_size  = MPI_Get_size(MpiComm)
    mpi_rank =  MPI_Get_rank(MpiComm)
    mpi_master= MPI_Get_master(MpiComm)
    !
    Nlat  = size(zeta,1)
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,4)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    !
    call assert_shape(zeta,[Nlat,Nso,Nso,Lfreq],"invert_gk_normal_tridiag_mpi","zeta")
    call assert_shape(Hk,[Nlso,Nlso],"invert_gk_normal_tridiag_mpi","Hk")
    call assert_shape(Gkout,[Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_normal_tridiag_mpi","Gkout")
    !
    !
    allocate(Sub(Nlat-1,Nso,Nso))
    allocate(Diag(Nlat,Nso,Nso))
    allocate(Over(Nlat-1,Nso,Nso))
    allocate(Gktmp(Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(Nlat,Nso,Nso))
    Gktmp=zero
    do i=1+mpi_rank,Lfreq,mpi_size
       call get_tridiag(Nlat,Nso,Hk,Sub,Diag,Over)
       Diag = zeta(:,:,:,i) - Diag
       if(allocated(Gembed))Diag = Diag - Gembed(:,:,:,i)
       call inv_tridiag(Nlat,Nso,-Sub,Diag,-Over,Gmatrix)
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb
                      jo = jorb + (jspin-1)*Norb
                      Gktmp(ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(ilat,io,jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout=zero
    call MPI_AllReduce(Gktmp, Gkout, size(Gkout), MPI_Double_Complex, MPI_Sum, MpiComm, mpi_ierr)
  end subroutine invert_gk_normal_tridiag_mpi
#endif














  !
  ! INVERT_GK_NORMAL(_MPI)
  !
  !SERIAL (OR PARALLEL ON K):
  subroutine invert_gk_superc(zeta,Hk,hk_symm,Gkout)
    complex(8),dimension(:,:,:,:,:),intent(in)      :: zeta    ![2][2][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:),intent(in)            :: Hk      ![2][Nspin*Norb][Nspin*Norb]
    logical,intent(in)                              :: hk_symm !
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![2][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![2][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable           :: Gmatrix ![2*Nspin*Norb][2*Nspin*Norb]
    integer                                         :: Nspin,Norb,Nso,Lfreq
    integer                                         :: i,iorb,jorb,ispin,jspin,io,jo
    !
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,5)
    Nso   = Nspin*Norb
    call assert_shape(zeta,[2,2,Nso,Nso,Lfreq],"invert_gk_superc","zeta")
    call assert_shape(Hk,[2,Nso,Nso],"invert_gk_superc","Hk")
    call assert_shape(Gkout,[2,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_superc","Gkout")
    !
    allocate(Gktmp(2,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(2*Nso,2*Nso))
    Gkout = zero
    Gktmp = zero
    do i=1,Lfreq
       Gmatrix  = zero
       Gmatrix(1:Nso,1:Nso)             = zeta(1,1,:,:,i) - Hk(1,:,:)
       Gmatrix(1:Nso,Nso+1:2*Nso)       = zeta(1,2,:,:,i)
       Gmatrix(Nso+1:2*Nso,1:Nso)       = zeta(2,1,:,:,i)
       Gmatrix(Nso+1:2*Nso,Nso+1:2*Nso) = zeta(2,2,:,:,i) - Hk(2,:,:) !+ Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   io = iorb + (ispin-1)*Norb
                   jo = jorb + (jspin-1)*Norb
                   Gktmp(1,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                   Gktmp(2,ispin,jspin,iorb,jorb,i) = Gmatrix(io,Nso+jo)
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout = Gktmp
  end subroutine invert_gk_superc

  !PARALLEL ON FREQ:
#ifdef _MPI
  subroutine invert_gk_superc_mpi(MpiComm,zeta,Hk,hk_symm,Gkout)
    integer                                         :: MpiComm
    complex(8),dimension(:,:,:,:,:),intent(in)      :: zeta    ![2][2][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:),intent(in)            :: Hk      ![2][Nspin*Norb][Nspin*Norb]
    logical,intent(in)                              :: hk_symm !
    complex(8),dimension(:,:,:,:,:,:),intent(inout) :: Gkout   ![2][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:),allocatable   :: Gktmp   ![2][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable           :: Gmatrix ![2*Nspin*Norb][2*Nspin*Norb]
    integer                                         :: Nspin,Norb,Nso,Lfreq
    integer                                         :: i,iorb,jorb,ispin,jspin,io,jo
    !
    !MPI setup:
    mpi_size  = MPI_Get_size(MpiComm)
    mpi_rank =  MPI_Get_rank(MpiComm)
    mpi_master= MPI_Get_master(MpiComm)
    !
    Nspin = size(Gkout,2)
    Norb  = size(Gkout,4)
    Lfreq = size(zeta,5)
    Nso   = Nspin*Norb
    call assert_shape(zeta,[2,2,Nso,Nso,Lfreq],"invert_gk_superc_mpi","zeta")
    call assert_shape(Hk,[2,Nso,Nso],"invert_gk_superc_mpi","Hk")
    call assert_shape(Gkout,[2,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_superc_mpi","Gkout")
    !
    allocate(Gktmp(2,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(2*Nso,2*Nso))
    Gkout = zero
    Gktmp = zero
    do i=1+mpi_rank,Lfreq,mpi_size
       Gmatrix  = zero
       Gmatrix(1:Nso,1:Nso)             = zeta(1,1,:,:,i) - Hk(1,:,:)
       Gmatrix(1:Nso,Nso+1:2*Nso)       = zeta(1,2,:,:,i)
       Gmatrix(Nso+1:2*Nso,1:Nso)       = zeta(2,1,:,:,i)
       Gmatrix(Nso+1:2*Nso,Nso+1:2*Nso) = zeta(2,2,:,:,i) - Hk(2,:,:) !+ Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   io = iorb + (ispin-1)*Norb
                   jo = jorb + (jspin-1)*Norb
                   Gktmp(1,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                   Gktmp(2,ispin,jspin,iorb,jorb,i) = Gmatrix(io,Nso+jo)
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout=zero
    call MPI_AllReduce(Gktmp, Gkout, size(Gkout), MPI_Double_Complex, MPI_Sum, MpiComm, mpi_ierr)
  end subroutine invert_gk_superc_mpi
#endif




  !
  ! INVERT_GK_NORMAL_INEQ(_MPI)
  !
  !SERIAL (OR PARALLEL ON K)
  subroutine invert_gk_superc_ineq(zeta,Hk,hk_symm,Gkout)
    complex(8),dimension(:,:,:,:,:,:),intent(in)      :: zeta    ![2][2][Nlat][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:),intent(in)              :: Hk      ![2][Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                                :: hk_symm !
    complex(8),dimension(:,:,:,:,:,:,:),intent(inout) :: Gkout   ![2][Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:,:),allocatable   :: Gktmp   ![2][Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable             :: Gmatrix ![2*Nlat*Nspin*Norb][2*Nlat*Nspin*Norb]
    integer                                           :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                           :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    Nlat  = size(zeta,3)
    Nspin = size(Gkout,3)
    Norb  = size(Gkout,5)
    Lfreq = size(zeta,6)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    call assert_shape(zeta,[2,2,Nlat,Nso,Nso,Lfreq],"invert_gk_superc_ineq","zeta")
    call assert_shape(Hk,[2,Nlso,Nlso],"invert_gk_superc_ineq","Hk")
    call assert_shape(Gkout,[2,Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_superc_ineq","Gkout")
    !
    allocate(Gktmp(2,Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(2*Nlso,2*Nlso))
    Gkout = zero
    Gktmp = zero
    do i=1,Lfreq
       Gmatrix  = zero
       Gmatrix(1:Nlso,1:Nlso)        = blocks_to_matrix(zeta(1,1,:,:,:,i),Nlat,Nso) - Hk(1,:,:)
       Gmatrix(1:Nlso,Nlso+1:2*Nlso) = blocks_to_matrix(zeta(1,2,:,:,:,i),Nlat,Nso)
       Gmatrix(Nlso+1:2*Nlso,1:Nlso) = blocks_to_matrix(zeta(2,1,:,:,:,i),Nlat,Nso)
       Gmatrix(Nlso+1:2*Nlso,Nlso+1:2*Nlso) = blocks_to_matrix(zeta(2,2,:,:,:,i),Nlat,Nso) - Hk(2,:,:)!+ Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                      jo = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                      Gktmp(1,ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                      Gktmp(2,ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,Nlso+jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout = Gktmp
  end subroutine invert_gk_superc_ineq


  !PARALLEL ON FREQ:
#ifdef _MPI
  subroutine invert_gk_superc_ineq_mpi(MpiComm,zeta,Hk,hk_symm,Gkout)
    integer                                           :: MpiComm
    complex(8),dimension(:,:,:,:,:,:),intent(in)      :: zeta    ![2][2][Nlat][Nspin*Norb][Nspin*Norb][Lfreq]
    complex(8),dimension(:,:,:),intent(in)              :: Hk      ![2][Nlat*Nspin*Norb][Nlat*Nspin*Norb]
    logical,intent(in)                                :: hk_symm !
    complex(8),dimension(:,:,:,:,:,:,:),intent(inout) :: Gkout   ![2][Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:,:,:,:,:,:),allocatable   :: Gktmp   ![2][Nlat][Nspin][Nspin][Norb][Norb][Lfreq]
    complex(8),dimension(:,:),allocatable             :: Gmatrix ![2*Nlat*Nspin*Norb][2*Nlat*Nspin*Norb]
    integer                                           :: Nlat,Nspin,Norb,Nso,Nlso,Lfreq
    integer                                           :: i,is,ilat,jlat,iorb,jorb,ispin,jspin,io,jo
    !
    !MPI setup:
    mpi_size  = MPI_Get_size(MpiComm)
    mpi_rank =  MPI_Get_rank(MpiComm)
    mpi_master= MPI_Get_master(MpiComm)
    !
    Nlat  = size(zeta,3)
    Nspin = size(Gkout,3)
    Norb  = size(Gkout,5)
    Lfreq = size(zeta,6)
    Nso   = Nspin*Norb
    Nlso  = Nlat*Nspin*Norb
    call assert_shape(zeta,[2,2,Nlat,Nso,Nso,Lfreq],"invert_gk_superc_ineq_mpi","zeta")
    call assert_shape(Hk,[2,Nlso,Nlso],"invert_gk_superc_ineq_mpi","Hk")
    call assert_shape(Gkout,[2,Nlat,Nspin,Nspin,Norb,Norb,Lfreq],"invert_gk_superc_ineq_mpi","Gkout")
    !
    allocate(Gktmp(2,Nlat,Nspin,Nspin,Norb,Norb,Lfreq))
    allocate(Gmatrix(2*Nlso,2*Nlso))
    Gkout = zero
    Gktmp = zero
    do i=1+mpi_rank,Lfreq,mpi_size
       Gmatrix  = zero
       Gmatrix(1:Nlso,1:Nlso)        = blocks_to_matrix(zeta(1,1,:,:,:,i),Nlat,Nso) - Hk(1,:,:)
       Gmatrix(1:Nlso,Nlso+1:2*Nlso) = blocks_to_matrix(zeta(1,2,:,:,:,i),Nlat,Nso)
       Gmatrix(Nlso+1:2*Nlso,1:Nlso) = blocks_to_matrix(zeta(2,1,:,:,:,i),Nlat,Nso)
       Gmatrix(Nlso+1:2*Nlso,Nlso+1:2*Nlso) = blocks_to_matrix(zeta(2,2,:,:,:,i),Nlat,Nso) - Hk(2,:,:) !+ Hk
       if(hk_symm) then
          call inv_sym(Gmatrix)
       else
          call inv(Gmatrix)  ! PAY ATTENTION HERE: it is not guaranteed that Gloc is a symmetric matrix
       end if
       !store the diagonal blocks directly into the tmp output 
       do ilat=1,Nlat
          do ispin=1,Nspin
             do jspin=1,Nspin
                do iorb=1,Norb
                   do jorb=1,Norb
                      io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                      jo = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                      Gktmp(1,ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,jo)
                      Gktmp(2,ilat,ispin,jspin,iorb,jorb,i) = Gmatrix(io,Nlso+jo)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
    Gkout=zero
    call MPI_AllReduce(Gktmp, Gkout, size(Gkout), MPI_Double_Complex, MPI_Sum, MpiComm, mpi_ierr)
  end subroutine invert_gk_superc_ineq_mpi
#endif







#ifdef _MPI
  function MPI_Get_size(comm) result(size)
    integer :: comm
    integer :: size,ierr
    call MPI_Comm_size(comm,size,ierr)
  end function MPI_Get_size



  function MPI_Get_rank(comm) result(rank)
    integer :: comm
    integer :: rank,ierr
    call MPI_Comm_rank(comm,rank,ierr)
  end function MPI_Get_rank



  function MPI_Get_master(comm) result(master)
    integer :: comm
    logical :: master
    integer :: rank,ierr
    call MPI_Comm_rank(comm,rank,ierr)
    master=.false.
    if(rank==0)master=.true.
  end function MPI_Get_master
#endif





  !####################################################################
  !                    COMPUTATIONAL ROUTINES
  !####################################################################
  !--------------------------------------------------------------------!
  !PURPOSE:
  ! Bcast/Reduce a vector of Blocks [Nlat][Nso][Nso] onto a matrix [Nlat*Nso][Nlat*Nso]
  !--------------------------------------------------------------------!
  function blocks_to_matrix(Vblocks,Nlat,Nso) result(Matrix)
    complex(8),dimension(Nlat,Nso,Nso)      :: Vblocks
    integer                                 :: Nlat,Nso
    complex(8),dimension(Nlat*Nso,Nlat*Nso) :: Matrix
    integer                                 :: i,j,ip
    Matrix=zero
    do ip=1,Nlat
       i = 1 + (ip-1)*Nso
       j = ip*Nso
       Matrix(i:j,i:j) =  Vblocks(ip,:,:)
    enddo
  end function blocks_to_matrix

  function matrix_to_blocks(Matrix,Nlat,Nso) result(Vblocks)
    complex(8),dimension(Nlat*Nso,Nlat*Nso) :: Matrix
    integer                                 :: Nlat,Nso
    complex(8),dimension(Nlat,Nso,Nso)      :: Vblocks
    integer                                 :: i,j,ip
    Vblocks=zero
    do ip=1,Nlat
       i = 1 + (ip-1)*Nso
       j = ip*Nso
       Vblocks(ip,:,:) = Matrix(i:j,i:j)
    enddo
  end function matrix_to_blocks






  !--------------------------------------------------------------------!
  !PURPOSE: select a single block of the diagonal from a large matrix.
  !--------------------------------------------------------------------!
  function select_block_Nlso(ip,Matrix,Nlat,Nso) result(Vblock)
    integer                                 :: ip
    complex(8),dimension(Nlat*Nso,Nlat*Nso) :: Matrix
    integer                                 :: Nlat,Nso
    complex(8),dimension(Nso,Nso)           :: Vblock
    integer                                 :: i,j
    Vblock=zero
    i = 1+(ip-1)*Nso
    j =       ip*Nso
    Vblock(:,:) = Matrix(i:j,i:j)
  end function select_block_nlso
  !
  function select_block_nnn(ip,Matrix,Nlat,Nspin,Norb) result(Vblock)
    integer                                          :: ip
    complex(8),dimension(Nlat,Nspin,Nspin,Norb,Norb) :: Matrix
    integer                                          :: Nlat,Nspin,Norb
    complex(8),dimension(Nspin*Norb,Nspin*Norb)      :: Vblock
    integer                                          :: is,js,ispin,jspin,iorb,jorb
    Vblock=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb !spin-orbit stride
                js = jorb + (jspin-1)*Norb !spin-orbit stride
                Vblock(is,js) = Matrix(ip,ispin,jspin,iorb,jorb)
             enddo
          enddo
       enddo
    enddo
  end function select_block_nnn








  !+-----------------------------------------------------------------------------+!
  !PURPOSE: 
  ! reshape a matrix from the [Nlso][Nlso] shape
  ! from/to the [Nlat][Nspin][Nspin][Norb][Norb] shape.
  ! _nlso2nnn : from [Nlso][Nlso] to [Nlat][Nspin][Nspin][Norb][Norb]  !
  ! _nso2nn   : from [Nso][Nso]   to [Nspin][Nspin][Norb][Norb]
  !+-----------------------------------------------------------------------------+!
  function d_nlso2nnn(Hlso,Nlat,Nspin,Norb) result(Hnnn)
    real(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb) :: Hlso
    integer                                            :: Nlat,Nspin,Norb
    real(8),dimension(Nlat,Nspin,Nspin,Norb,Norb)      :: Hnnn
    integer                                            :: iorb,ispin,ilat,is
    integer                                            :: jorb,jspin,jlat,js
    Hnnn=zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   Hnnn(ilat,ispin,jspin,iorb,jorb) = Hlso(is,js)
                enddo
             enddo
          enddo
       enddo
    enddo
  end function d_nlso2nnn
  function c_nlso2nnn(Hlso,Nlat,Nspin,Norb) result(Hnnn)
    complex(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb) :: Hlso
    integer                                               :: Nlat,Nspin,Norb
    complex(8),dimension(Nlat,Nspin,Nspin,Norb,Norb)      :: Hnnn
    integer                                               :: iorb,ispin,ilat,is
    integer                                               :: jorb,jspin,jlat,js
    Hnnn=zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   Hnnn(ilat,ispin,jspin,iorb,jorb) = Hlso(is,js)
                enddo
             enddo
          enddo
       enddo
    enddo
  end function c_nlso2nnn

  function d_nso2nn(Hso,Nspin,Norb) result(Hnn)
    real(8),dimension(Nspin*Norb,Nspin*Norb) :: Hso
    integer                                  :: Nspin,Norb
    real(8),dimension(Nspin,Nspin,Norb,Norb) :: Hnn
    integer                                  :: iorb,ispin,is
    integer                                  :: jorb,jspin,js
    Hnn=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb  !spin-orbit stride
                js = jorb + (jspin-1)*Norb  !spin-orbit stride
                Hnn(ispin,jspin,iorb,jorb) = Hso(is,js)
             enddo
          enddo
       enddo
    enddo
  end function d_nso2nn
  function c_nso2nn(Hso,Nspin,Norb) result(Hnn)
    complex(8),dimension(Nspin*Norb,Nspin*Norb) :: Hso
    integer                                     :: Nspin,Norb
    complex(8),dimension(Nspin,Nspin,Norb,Norb) :: Hnn
    integer                                     :: iorb,ispin,is
    integer                                     :: jorb,jspin,js
    Hnn=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb  !spin-orbit stride
                js = jorb + (jspin-1)*Norb  !spin-orbit stride
                Hnn(ispin,jspin,iorb,jorb) = Hso(is,js)
             enddo
          enddo
       enddo
    enddo
  end function c_nso2nn




  !+-----------------------------------------------------------------------------+!
  !PURPOSE: 
  ! reshape a matrix from the [Nlat][Nspin][Nspin][Norb][Norb] shape
  ! from/to the [Nlso][Nlso] shape.
  ! _nnn2nlso : from [Nlat][Nspin][Nspin][Norb][Norb] to [Nlso][Nlso]
  ! _nn2nso   : from [Nspin][Nspin][Norb][Norb]       to [Nso][Nso]
  !+-----------------------------------------------------------------------------+!
  function d_nnn2nlso(Hnnn,Nlat,Nspin,Norb) result(Hlso)
    real(8),dimension(Nlat,Nspin,Nspin,Norb,Norb)      :: Hnnn
    integer                                            :: Nlat,Nspin,Norb
    real(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb) :: Hlso
    integer                                            :: iorb,ispin,ilat,is
    integer                                            :: jorb,jspin,jlat,js
    Hlso=zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   Hlso(is,js) = Hnnn(ilat,ispin,jspin,iorb,jorb)
                enddo
             enddo
          enddo
       enddo
    enddo
  end function d_nnn2nlso

  function c_nnn2nlso(Hnnn,Nlat,Nspin,Norb) result(Hlso)
    complex(8),dimension(Nlat,Nspin,Nspin,Norb,Norb)      :: Hnnn
    integer                                               :: Nlat,Nspin,Norb
    complex(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb) :: Hlso
    integer                                               :: iorb,ispin,ilat,is
    integer                                               :: jorb,jspin,jlat,js
    Hlso=zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Norb*Nspin !lattice-spin-orbit stride
                   Hlso(is,js) = Hnnn(ilat,ispin,jspin,iorb,jorb)
                enddo
             enddo
          enddo
       enddo
    enddo
  end function c_nnn2nlso

  function d_nn2nso(Hnn,Nspin,Norb) result(Hso)
    real(8),dimension(Nspin,Nspin,Norb,Norb) :: Hnn
    integer                                  :: Nspin,Norb
    real(8),dimension(Nspin*Norb,Nspin*Norb) :: Hso
    integer                                  :: iorb,ispin,is
    integer                                  :: jorb,jspin,js
    Hso=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb  !spin-orbit stride
                js = jorb + (jspin-1)*Norb  !spin-orbit stride
                Hso(is,js) = Hnn(ispin,jspin,iorb,jorb)
             enddo
          enddo
       enddo
    enddo
  end function d_nn2nso

  function c_nn2nso(Hnn,Nspin,Norb) result(Hso)
    complex(8),dimension(Nspin,Nspin,Norb,Norb) :: Hnn
    integer                                     :: Nspin,Norb
    complex(8),dimension(Nspin*Norb,Nspin*Norb) :: Hso
    integer                                     :: iorb,ispin,is
    integer                                     :: jorb,jspin,js
    Hso=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb  !spin-orbit stride
                js = jorb + (jspin-1)*Norb  !spin-orbit stride
                Hso(is,js) = Hnn(ispin,jspin,iorb,jorb)
             enddo
          enddo
       enddo
    enddo
  end function c_nn2nso


end module DMFT_GK
