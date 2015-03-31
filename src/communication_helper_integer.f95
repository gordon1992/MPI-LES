module communication_helper_integer
#ifdef MPI
use communication_helper_mpi
#endif
#ifdef GMCF
use communication_helper_gmcf
#endif
implicit none

! May not be kept as up to date as communication_helper_real since communication_helper_integer is
! just to test things out!

contains

subroutine sideflowRightLeftInteger(array, procPerRow, colToSend, colToRecv, topThickness, bottomThickness)
    implicit none
    integer, intent(in) :: procPerRow, colToSend, colToRecv, topThickness, bottomThickness
    integer(kind=4), dimension(:,:,:), intent(inout) :: array
    integer(kind=4), dimension(:,:), allocatable :: leftRecv, rightSend
    integer :: r, d, commWith, rowCount, depthSize
    rowCount = size(array, 1) - topThickness - bottomThickness
    depthSize = size(array, 3)
    if (isLeftmostColumn(procPerRow)) then
        allocate(leftRecv(rowCount, depthSize))
        commWith = rank + procPerRow - 1
        call MPI_Recv(leftRecv, rowCount*depthSize, MPI_INT, commWith, rightSideTag, &
                      communicator, status, ierror)
        call checkMPIError()
        do r=1, rowCount
            do d=1, depthSize
                array(r+topThickness, colToRecv, d) = leftRecv(r, d)
            end do
        end do
        deallocate(leftRecv)
    else if (isRightmostColumn(procPerRow)) then
        allocate(rightSend(rowCount, depthSize))
        commWith = rank - procPerRow + 1
        do r=1, rowCount
            do d=1, depthSize
                rightSend(r, d) = array(r+topThickness, colToSend, d)
            end do
        end do
        call MPI_Send(rightSend, rowCount*depthSize, MPI_INT, commWith, rightSideTag, &
                      communicator, ierror)
        call checkMPIError()
        deallocate(rightSend)
    end if
end subroutine sideflowRightLeftInteger

subroutine sideflowLeftRightInteger(array, procPerRow, colToSend, colToRecv, topThickness, bottomThickness)
    implicit none
    integer, intent(in) :: procPerRow, colToSend, colToRecv, topThickness, bottomThickness
    integer(kind=4), dimension(:,:,:), intent(inout) :: array
    integer(kind=4), dimension(:,:), allocatable :: leftSend, rightRecv
    integer :: r, d, commWith, rowCount, depthSize
    rowCount = size(array, 1) - topThickness - bottomThickness
    depthSize = size(array, 3)
    if (isLeftmostColumn(procPerRow)) then
        allocate(leftSend(rowCount, depthSize))
        commWith = rank + procPerRow - 1
        do r=1, rowCount
            do d=1, depthSize
                leftSend(r, d) = array(r+topThickness, colToSend, d)
            end do
        end do
        call MPI_Send(leftSend, rowCount*depthSize, MPI_INT, commWith, leftSideTag, &
                      communicator, ierror)
        call checkMPIError()
        deallocate(leftSend)
    else if (isRightmostColumn(procPerRow)) then
        allocate(rightRecv(rowCount, depthSize))
        commWith = rank - procPerRow + 1
        call MPI_Recv(rightRecv, rowCount*depthSize, MPI_INT, commWith, leftSideTag, &
                      communicator, status, ierror)
        call checkMPIError()
        do r=1, rowCount
            do d=1, depthSize
                array(r+topThickness, colToRecv, d) = rightRecv(r, d)
            end do
        end do
        deallocate(rightRecv)
    end if
end subroutine sideflowLeftRightInteger

subroutine calculateCorners(array, procPerRow, leftThickness, rightThickness, &
                            topThickness, bottomThickness)
    implicit none
    integer, intent(in) :: procPerRow, leftThickness, rightThickness, &
                           topThickness, bottomThickness
    integer, dimension(:,:), intent(inout) :: array
    integer :: r, c
    if (.not. isTopRow(procPerRow) .and. .not. isLeftmostColumn(procPerRow)) then
        ! There is a top left corner to specify
        do r=topThickness,1,-1
            do c=leftThickness,1,-1
                array(r, c) = (array(r+1, c) + array(r, c+1) + array(r+1, c+1)) / 3
            end do
        end do
    end if
    if (.not. isTopRow(procPerRow) .and. .not. isRightmostColumn(procPerRow)) then
        ! There is a top right corner to specify
        do r=topThickness,1,-1
            do c=size(array,2)-rightThickness+1,size(array,2)
                array(r, c) = (array(r+1, c) + array(r, c-1) + array(r+1, c-1)) / 3
            end do
        end do
    end if
    if (.not. isBottomRow(procPerRow) .and. .not. isLeftmostColumn(procPerRow)) then
        ! There is a bottom left corner to specify
        do r=size(array,1)-bottomThickness+1,size(array,1)
            do c=leftThickness,1,-1
                array(r, c) = (array(r-1, c) + array(r, c+1) + array(r-1, c+1)) / 3
            end do
        end do
    end if
    if (.not. isBottomRow(procPerRow) .and. .not. isRightmostColumn(procPerRow)) then
        ! There is a bottom right corner to specify
        do r=size(array,1)-bottomThickness+1,size(array,1)
            do c=size(array,2)-rightThickness+1,size(array,2)
                array(r, c) = (array(r, c-1) + array(r-1, c) - array(r-1, c-1)) / 2
            end do
       end do
    end if
end subroutine calculateCorners

subroutine exchangeIntegerHalos(array, procPerRow, neighbours, leftThickness, &
                                rightThickness, topThickness, &
                                bottomThickness)
    implicit none
    integer, dimension(:,:,:), intent(inout) :: array
    integer, dimension(:), intent(in) :: neighbours
    integer, intent(in) :: procPerRow, leftThickness, rightThickness, topThickness, bottomThickness
    integer :: i, commWith, r, c, d, rowCount, colCount, depthSize, requests(8)
    integer, dimension(:,:,:), allocatable :: leftRecv, leftSend, rightSend, rightRecv
    integer, dimension(:,:,:), allocatable :: topRecv, topSend, bottomSend, bottomRecv
    if (size(neighbours, 1) .lt. 4) then
        print*, "Error: cannot have a 4-way halo exchange with less than 4 neighbours"
        call finalise_mpi()
        return
    end if
    rowCount = size(array, 1) - topThickness - bottomThickness
    colCount = size(array, 2) - leftThickness - rightThickness
    depthSize = size(array, 3)
    allocate(leftRecv(rowCount, rightThickness, depthSize))
    allocate(rightSend(rowCount, leftThickness, depthSize))
    allocate(rightRecv(rowCount, leftThickness, depthSize))
    allocate(leftSend(rowCount, rightThickness, depthSize))
    allocate(topRecv(bottomThickness, colCount, depthSize))
    allocate(bottomSend(topThickness, colCount, depthSize))
    allocate(bottomRecv(topThickness, colCount, depthSize))
    allocate(topSend(bottomThickness, colCount, depthSize))
    do i=1,8
        requests(i)= -1
    end do
    ! Top edge to send, bottom edge to receive
    commWith = neighbours(topNeighbour)
    if (commWith .ne. -1) then
        !print*, 'rank ', rank, ' communicating with top neighbour ', commWith
        do r=1, bottomThickness
            do c=1, colCount
                do d=1, depthSize
                    topSend(r, c, d) = array(r + topThickness, c+leftThickness, d)
                end do
            end do
        end do
        call MPI_ISend(topSend, bottomThickness*colCount*depthSize, MPI_INT, commWith, topTag, &
                      communicator, requests(1), ierror)
        call checkMPIError()
        call MPI_IRecv(bottomRecv, topThickness*colCount*depthSize, MPI_INT, commWith, bottomTag, &
                      communicator, requests(2), ierror)
        call checkMPIError()
    end if
    ! Bottom edge to send, top edge to receive
    commWith = neighbours(bottomNeighbour)
    if (commWith .ne. -1) then
        !print*, 'rank ', rank, ' communicating with bottom neighbour ', commWith
        do r=1, topThickness
            do c=1, colCount
                do d=1, depthSize
                    bottomSend(r, c, d) = array(size(array, 1) - bottomThickness - topThickness + r, &
                                          c+leftThickness, &
                                          d)
                end do
            end do
        end do
        call MPI_IRecv(topRecv, bottomThickness*colCount*depthSize, MPI_INT, commWith, topTag, &
                      communicator, requests(3), ierror)
        call checkMPIError()
        call MPI_ISend(bottomSend, topThickness*colCount*depthSize, MPI_INT, commWith, bottomTag, &
                      communicator, requests(4), ierror)
        call checkMPIError()
    end if
    ! Left edge to send, right edge to receive
    commWith = neighbours(leftNeighbour)
    if (commWith .ne. -1) then
        !print*, 'rank ', rank, ' communicating with left neighbour ', commWith
        do r=1, rowCount
            do c=1, rightThickness
                do d=1, depthSize
                    leftSend(r, c, d) = array(r+topThickness, c + leftThickness, d)
                end do
            end do
        end do
        call MPI_ISend(leftSend, rightThickness*rowCount*depthSize, MPI_INT, commWith, leftTag, &
                      communicator, requests(5), ierror)
        call checkMPIError()
        call MPI_IRecv(rightRecv, leftThickness*rowCount*depthSize, MPI_INT, commWith, rightTag, &
                      communicator, requests(6), ierror)
        call checkMPIError()
    end if
    ! Right edge to send, left edge to receive
    commWith = neighbours(rightNeighbour)
    if (commWith .ne. -1) then
        !print*, 'rank ', rank, ' communicating with right neighbour ', commWith
        do r=1, rowCount
            do c=1, leftThickness
                do d=1, depthSize
                    rightSend(r, c, d) = array(r+topThickness, &
                                               size(array, 2) - rightThickness - leftThickness + c,&
                                               d)
                end do
            end do
        end do
        call MPI_IRecv(leftRecv, rightThickness*rowCount*depthSize, MPI_INT, commWith, leftTag, &
                      communicator, requests(7), ierror)
        call checkMPIError()
        call MPI_ISend(rightSend, leftThickness*rowCount*depthSize, MPI_INT, commWith, rightTag, &
                      communicator, requests(8), ierror)
        call checkMPIError()
    end if
    do i=1,8
        if (.not. requests(i) .eq. -1) then
            call MPI_Wait(requests(i), status, ierror)
            call checkMPIError()
        end if
    end do
    if (.not. isTopRow(procPerRow)) then
        ! Top edge to send, bottom edge to receive
        commWith = rank - procPerRow
        do r=1, topThickness
            do c=1, colCount
                do d=1, depthSize
                    array(r, c+leftThickness, d) = bottomRecv(r, c, d)
                end do
            end do
        end do
    end if
    if (.not. isBottomRow(procPerRow)) then
        ! Bottom edge to send, top edge to receive
        do r=1, bottomThickness
            do c=1, colCount
                do d=1, depthSize
                    array(size(array, 1) - bottomThickness + r, c+leftThickness, d) = topRecv(r, c, d)
                end do
            end do
        end do
    end if
    if (.not. isLeftmostColumn(procPerRow)) then
        ! Left edge to send, right edge to receive
        do r=1, rowCount
            do c=1, leftThickness
                do d=1, depthSize
                    array(r+topThickness, c, d) = rightRecv(r, c, d)
                end do
            end do
        end do
    end if
    if (.not. isRightmostColumn(procPerRow)) then
        ! Right edge to send, left edge to receive
        do r=1, rowCount
            do c=1, rightThickness
                do d=1, depthSize
                    array(r+topThickness, size(array, 2) - rightThickness + c, d) = leftRecv(r, c, d)
                end do
            end do
        end do
    end if
    do i=1, depthSize
        call calculateCorners(array(:,:,i), procPerRow, leftThickness, &
                              rightThickness, topThickness, bottomThickness)
    end do
    deallocate(leftRecv)
    deallocate(leftSend)
    deallocate(rightSend)
    deallocate(rightRecv)
    deallocate(topRecv)
    deallocate(topSend)
    deallocate(bottomSend)
    deallocate(bottomRecv)
end subroutine exchangeIntegerHalos

end module
