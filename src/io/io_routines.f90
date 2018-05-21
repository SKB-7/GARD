!>------------------------------------------------------------
!!  Basic file input/output routines
!!
!!  @details
!!  Primary use is io_read2d/3d
!!  io_write* routines are more used for debugging
!!  model output is performed in the output module
!!
!!  Generic interfaces are supplied for io_read and io_write
!!  but most code still uses the explicit read/write 2d/3d/etc.
!!  this keeps the code a little more obvious (at least 2D vs 3D)
!!
!!  @author
!!  Ethan Gutmann (gutmann@ucar.edu)
!!
!!------------------------------------------------------------
submodule(io_routines) io_routines_implementation
    use netcdf
    use model_constants

    implicit none

contains

    !>------------------------------------------------------------
    !! Tests to see if a file exists
    !!
    !! @param filename name of file to look for
    !! @retval logical true if file exists, false if it doesn't
    !!
    !!------------------------------------------------------------
    module logical function file_exists(filename)
        character(len=*), intent(in) :: filename
        inquire(file=filename,exist=file_exists)
    end function file_exists

    !>------------------------------------------------------------
    !! Tests to see if a variable is present in a netcdf file
    !! returns true of it is, false if it isn't
    !!
    !! @param filename name of NetCDF file
    !! @param variable_name name of variable to search for in filename
    !! @retval logical True if variable_name is present in filename
    !!
    !!------------------------------------------------------------
    logical function io_variable_is_present(filename,variable_name)
        character(len=*), intent(in) :: filename
        character(len=*), intent(in) :: variable_name
        integer :: ncid,err,varid

        call check(nf90_open(filename, NF90_NOWRITE, ncid))
        err = nf90_inq_varid(ncid, variable_name, varid)
        call check( nf90_close(ncid),filename )

        io_variable_is_present = (err==NF90_NOERR)
    end function io_variable_is_present

    !>------------------------------------------------------------
    !! Finds the nearest time step in a file to a given MJD
    !! Uses the "time" variable from filename.
    !!
    !! @param filename  Name of an ICAR NetCDF output file
    !! @param mjd       Modified Julian day to find.
    !!                  If on a noleap calendar, it assumes MJD is days since 1900
    !! @retval integer  Index into the time dimension (last dim)
    !!
    !!------------------------------------------------------------
    integer function io_nearest_time_step(filename, mjd)
        character(len=*),intent(in) :: filename
        double precision, intent(in) :: mjd
        double precision, allocatable, dimension(:) :: time_data
        integer :: ncid,varid,dims(1),ntimes,i

        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, "time", varid),                 trim(filename)//" : time")
        call check(nf90_inquire_variable(ncid, varid, dimids = dims),   trim(filename)//" : time dims")
        call check(nf90_inquire_dimension(ncid, dims(1), len = ntimes), trim(filename)//" : inq time dim")

        allocate(time_data(ntimes))
        call check(nf90_get_var(ncid, varid, time_data),trim(filename)//"reading time")
        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

        io_nearest_time_step=1
        do i=1,ntimes
            ! keep track of every time that occurs before the mjd we are looking for
            ! the last one will be the date we want to use.
            if ((mjd - time_data(i)) > -1e-4) then
                io_nearest_time_step=i
            endif
        end do
        deallocate(time_data)
    end function io_nearest_time_step


    !>------------------------------------------------------------
    !! Read the dimensions of a variable in a given netcdf file
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to find the dimensions of
    !! @param[out] dims     Allocated array to store output
    !! @retval dims(:) dims[1]=ndims, dims[i+1]=length of dimension i for a given variable
    !!
    !!------------------------------------------------------------
    module subroutine io_getdims(filename,varname,dims)
        implicit none
        character(len=*), intent(in) :: filename,varname
        integer,intent(out) :: dims(:)

        ! internal variables
        integer :: ncid,varid,numDims,dimlen,i
        integer,dimension(io_maxDims) :: dimIds

        ! open the netcdf file
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),varname)
        ! find the number of dimensions
        call check(nf90_inquire_variable(ncid, varid, ndims = numDims),varname)
        ! find the dimension IDs
        call check(nf90_inquire_variable(ncid, varid, dimids = dimIds(:numDims)),varname)
        dims(1)=numDims
        ! finally, find the length of each dimension
        do i=1,numDims
            call check(nf90_inquire_dimension(ncid, dimIds(i), len = dimlen))
            dims(i+1)=dimlen
        end do
        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename )

    end subroutine io_getdims

    !>------------------------------------------------------------
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>6)
    !!   e.g. we may only want one time slice from a 6d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 6-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 6-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read6d(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(out),allocatable :: data_in(:,:,:,:,:,:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo !will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1:6)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2),diminfo(3),diminfo(4),diminfo(5),diminfo(6),diminfo(7)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 6 dimensions (typically this will be time)
        ! and good luck if you have more than 6 dimensions...
        if (diminfo(1)>6) then
            diminfo(8:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ]),&   ! for all dims, stride = 1     "  implied do loop
                                    trim(filename)//":"//trim(varname)) !pass file:var to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif
        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read6d

    !>------------------------------------------------------------
    !! Same as io_read6d but for 4-dimensional data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>3)
    !!   e.g. we may only want one time slice from a 3d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 4-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 3-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read4d(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(out),allocatable :: data_in(:,:,:,:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo !will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1:4)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2),diminfo(3),diminfo(4),diminfo(5)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 3 dimensions (typically this will be time)
        if (diminfo(1)>4) then
            diminfo(6:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ]),&   ! for all dims, stride = 1     "  implied do loop
                                    trim(filename)//":"//trim(varname)) !pass file:var to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif
        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read4d


    !>------------------------------------------------------------
    !! Same as io_read6d but for 3-dimensional data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>3)
    !!   e.g. we may only want one time slice from a 3d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 3-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 3-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read3d(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(out),allocatable :: data_in(:,:,:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo !will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1:3)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2),diminfo(3),diminfo(4)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 3 dimensions (typically this will be time)
        if (diminfo(1)>3) then
            diminfo(5:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ]),&   ! for all dims, stride = 1     "  implied do loop
                                    trim(filename)//":"//trim(varname)) !pass file:var to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif
        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read3d


    !>------------------------------------------------------------
    !! Same as io_read3d but for 2-dimensional data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>2)
    !!   e.g. we may only want one time slice from a 2d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 2-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 2-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read2d(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(out),allocatable :: data_in(:,:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo ! will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1:2)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2),diminfo(3)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 3 dimensions (typically this will be time)
        if (diminfo(1)>2) then
            diminfo(4:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ] ), & ! for all dims, stride = 1      " implied do loop
                                    trim(filename)//":"//trim(varname)) !pass varname to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read2d

    !>------------------------------------------------------------
    !! Same as io_read2d but for integer data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>2)
    !!   e.g. we may only want one time slice from a 2d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 2-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 2-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read2di(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        integer,intent(out),allocatable :: data_in(:,:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo ! will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1:2)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2),diminfo(3)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 3 dimensions (typically this will be time)
        if (diminfo(1)>2) then
            diminfo(4:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ] ), & ! for all dims, stride = 1      " implied do loop
                                    trim(filename)//":"//trim(varname)) !pass varname to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),varname)
        endif

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read2di

    !>------------------------------------------------------------
    !! Same as io_read3d but for 1-dimensional data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>1)
    !!   e.g. we may only want one time slice from a 1d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 1-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 1-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read1d(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(out),allocatable :: data_in(:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo ! will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 1 dimensions (typically this will be time)
        if (diminfo(1)>1) then
            diminfo(3:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ] ), & ! for all dims, stride = 1      " implied do loop
                                    trim(filename)//":"//trim(varname)) !pass varname to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read1d

    !>------------------------------------------------------------
    !! Same as io_read1d but for double precision data
    !!
    !! Reads in a variable from a netcdf file, allocating memory in data_in for it.
    !!
    !! if extradim is provided specifies this index for any extra dimensions (dims>1)
    !!   e.g. we may only want one time slice from a 1d variable
    !!
    !! @param   filename    Name of NetCDF file to look at
    !! @param   varname     Name of the NetCDF variable to read
    !! @param[out] data_in     Allocatable 1-dimensional array to store output
    !! @param   extradim    OPTIONAL: specify the position to read for any extra (e.g. time) dimension
    !! @retval data_in     Allocated 1-dimensional array with the netCDF data
    !!
    !!------------------------------------------------------------
    module subroutine io_read1dd(filename,varname,data_in,extradim)
        implicit none
        ! This is the name of the data_in file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        double precision,intent(out),allocatable :: data_in(:)
        integer, intent(in),optional :: extradim
        integer, dimension(io_maxDims)  :: diminfo ! will hold dimension lengths
        integer, dimension(io_maxDims)  :: dimstart
        ! This will be the netCDF ID for the file and data_in variable.
        integer :: ncid, varid,i

        if (present(extradim)) then
            dimstart=extradim
            dimstart(1)=1
        else
            dimstart=1
        endif

        ! Read the dimension lengths
        diminfo = 1
        call io_getdims(filename,varname,diminfo)
        allocate(data_in(diminfo(2)))
        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)
        ! Get the varid of the data_in variable, based on its name.
        call check(nf90_inq_varid(ncid, varname, varid),trim(filename)//":"//trim(varname))

        ! Read the data_in. skip the slowest varying indices if there are more than 1 dimensions (typically this will be time)
        if (diminfo(1)>1) then
            diminfo(3:diminfo(1)+1)=1 ! set count for extra dims to 1
            call check(nf90_get_var(ncid, varid, data_in,&
                                    dimstart(1:diminfo(1)), &               ! start  = 1 or extradim
                                    [ (diminfo(i+1), i=1,diminfo(1)) ],&    ! count=n or 1 created through an implied do loop
                                    [ (1,            i=1,diminfo(1)) ] ), & ! for all dims, stride = 1      " implied do loop
                                    trim(filename)//":"//trim(varname)) !pass varname to check so it can give us more info
        else
            call check(nf90_get_var(ncid, varid, data_in),trim(filename)//":"//trim(varname))
        endif

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid),filename)

    end subroutine io_read1dd



    !>------------------------------------------------------------
    !! Write a 6-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    6-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write6d(filename,varname,data_out, dimnames)
        implicit none
        ! This is the name of the file and variable we will write.
        character(len=*), intent(in) :: filename, varname
        real,intent(in) :: data_out(:,:,:,:,:,:)
        character(len=*), optional, dimension(6), intent(in) :: dimnames

        ! We are writing 6D data, a nx, nz, ny, na, nb, nc grid.
        integer :: nx,ny,nz, na,nb,nc
        integer, parameter :: ndims = 6
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)
        character(len=MAXDIMLENGTH), dimension(6) :: dims

        if (present(dimnames)) then
            dims = dimnames
        else
            dims = ["x","y","z","a","b","c"]
        endif

        nx=size(data_out,1)
        nz=size(data_out,2)
        ny=size(data_out,3)
        na=size(data_out,4)
        nb=size(data_out,5)
        nc=size(data_out,6)

        ! Open the file. NF90_CLOBBER tells netCDF we want overwrite existing files
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, trim(dims(1)), nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(2)), nz, temp_dimid) )
            dimids(2)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(3)), ny, temp_dimid) )
            dimids(3)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(4)), na, temp_dimid) )
            dimids(4)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(5)), nb, temp_dimid) )
            dimids(5)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(6)), nc, temp_dimid) )
            dimids(6)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        !write the actual data to the file
        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid), filename)
    end subroutine io_write6d

    !>------------------------------------------------------------
    !! Same as io_write6d but for 4-dimensional data
    !!
    !! Write a 4-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    4-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write4d(filename,varname,data_out, dimnames)
        implicit none
        ! This is the name of the file and variable we will write.
        character(len=*), intent(in) :: filename, varname
        real,intent(in) :: data_out(:,:,:,:)
        character(len=*), optional, dimension(4), intent(in) :: dimnames

        character(len=MAXDIMLENGTH), dimension(4) :: dims
        ! We are writing 4D data, assume a nx x nz x ny x nr grid.
        integer :: nx,ny,nz,nr
        integer, parameter :: ndims = 4
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)
        nz=size(data_out,2)
        ny=size(data_out,3)
        nr=size(data_out,4)

        if (present(dimnames)) then
            dims = dimnames
        else
            dims = ["x","y","z","t"]
        endif

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename)

            ! define the dimensions
            call check( nf90_def_dim(ncid, trim(dims(1)), nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(2)), nz, temp_dimid) )
            dimids(2)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(3)), ny, temp_dimid) )
            dimids(3)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(4)), nr, temp_dimid) )
            dimids(4)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        ! write the actual data to the file
        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid), filename)
    end subroutine io_write4d

    !>------------------------------------------------------------
    !! Same as io_write4d but for integer data
    !!
    !! Write a 4-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    4-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write4di(filename,varname,data_out)
        implicit none
        ! This is the name of the file and variable we will write.
        character(len=*), intent(in) :: filename, varname
        integer,intent(in) :: data_out(:,:,:,:)

        ! We are writing 4D data, assume a nx x nz x ny x nr grid.
        integer :: nx,ny,nz,nr
        integer, parameter :: ndims = 4
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)
        nz=size(data_out,2)
        ny=size(data_out,3)
        nr=size(data_out,4)

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename)

            ! define the dimensions
            call check( nf90_def_dim(ncid, "x", nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, "y", nz, temp_dimid) )
            dimids(2)=temp_dimid
            call check( nf90_def_dim(ncid, "z", ny, temp_dimid) )
            dimids(3)=temp_dimid
            call check( nf90_def_dim(ncid, "t", nr, temp_dimid) )
            dimids(4)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_INT, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        ! write the actual data to the file
        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid), filename)
    end subroutine io_write4di


    !>------------------------------------------------------------
    !! Same as io_write6d but for 3-dimensional data
    !!
    !! Write a 3-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    3-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write3d(filename,varname,data_out, dimnames)
        implicit none
        ! This is the name of the file and variable we will write.
        character(len=*), intent(in) :: filename, varname
        real,intent(in) :: data_out(:,:,:)
        character(len=*), optional, dimension(3), intent(in) :: dimnames

        character(len=MAXDIMLENGTH), dimension(3) :: dims
        ! We are reading 2D data, a nx x ny grid.
        integer :: nx,ny,nz
        integer, parameter :: ndims = 3
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)
        nz=size(data_out,2)
        ny=size(data_out,3)

        if (present(dimnames)) then
            dims = dimnames
        else
            dims = ["x","y","t"]
        endif

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, trim(dims(1)), nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(2)), nz, temp_dimid) )
            dimids(2)=temp_dimid
            call check( nf90_def_dim(ncid, trim(dims(3)), ny, temp_dimid) )
            dimids(3)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        ! write the actual data to the file
        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid), filename)
    end subroutine io_write3d

    !>------------------------------------------------------------
    !! Same as io_write3d but for integer arrays
    !!
    !! Write a 3-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    3-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write3di(filename,varname,data_out)
        implicit none
        ! This is the name of the data file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        integer,intent(in) :: data_out(:,:,:)

        ! We are reading 2D data, a nx x ny grid.
        integer :: nx,ny,nz
        integer, parameter :: ndims = 3
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)
        nz=size(data_out,2)
        ny=size(data_out,3)

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, "x", nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, "y", nz, temp_dimid) )
            dimids(2)=temp_dimid
            call check( nf90_def_dim(ncid, "t", ny, temp_dimid) )
            dimids(3)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_INT, dimids, varid), trim(filename)//":"//trim(varname) )
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        call check( nf90_put_var(ncid, varid, data_out),trim(filename)//":"//trim(varname) )

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid) )
    end subroutine io_write3di

    !>------------------------------------------------------------
    !! Same as io_write3d but for 2-dimensional arrays
    !!
    !! Write a 2-dimensional variable to a netcdf file
    !!
    !! Create a netcdf file:filename with a variable:varname and write data_out to it
    !!
    !! @param   filename    Name of NetCDF file to write/create
    !! @param   varname     Name of the NetCDF variable to write
    !! @param   data_out    2-dimensional array to write to the file
    !!
    !!------------------------------------------------------------
    module subroutine io_write2d(filename,varname,data_out)
        implicit none
        ! This is the name of the data file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(in) :: data_out(:,:)

        ! We are reading 2D data, a nx x ny grid.
        integer :: nx,ny
        integer, parameter :: ndims = 2
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)
        ny=size(data_out,2)

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, "x", nx, temp_dimid) )
            dimids(1)=temp_dimid
            call check( nf90_def_dim(ncid, "y", ny, temp_dimid) )
            dimids(2)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid) )
    end subroutine io_write2d

    module subroutine io_write1dd(filename,varname,data_out, dimname)
        implicit none
        ! This is the name of the data file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        double precision,intent(in) :: data_out(:)
        character(len=*), intent(in), optional :: dimname
        character(len=64) :: dim

        ! We are reading 2D data, a nx x ny grid.
        integer :: nx
        integer, parameter :: ndims = 1
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        dim="t"
        if (present(dimname)) dim=dimname

        nx=size(data_out,1)

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, dim, nx, temp_dimid) )
            dimids(1)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid) )
    end subroutine io_write1dd


    module subroutine io_write1d(filename,varname,data_out)
        implicit none
        ! This is the name of the data file and variable we will read.
        character(len=*), intent(in) :: filename, varname
        real,intent(in) :: data_out(:)

        ! We are reading 2D data, a nx x ny grid.
        integer :: nx
        integer, parameter :: ndims = 1
        ! This will be the netCDF ID for the file and data variable.
        integer :: ncid, varid,temp_dimid,dimids(ndims)

        nx=size(data_out,1)

        ! Open the file. NF90_NOWRITE tells netCDF we want read-only access to
        ! the file.
        if (file_exists(filename)) then
            call check( nf90_open(filename, NF90_WRITE, ncid) )
            call check( nf90_redef(ncid) )
        else
            call check( nf90_create(filename, NF90_CLOBBER, ncid), filename )

            ! define the dimensions
            call check( nf90_def_dim(ncid, "x", nx, temp_dimid) )
            dimids(1)=temp_dimid
        endif

        ! Create the variable returns varid of the data variable
        call check( nf90_def_var(ncid, varname, NF90_REAL, dimids, varid), trim(filename)//":"//trim(varname))
        ! End define mode. This tells netCDF we are done defining metadata.
        call check( nf90_enddef(ncid) )

        call check( nf90_put_var(ncid, varid, data_out), trim(filename)//":"//trim(varname))

        ! Close the file, freeing all resources.
        call check( nf90_close(ncid) )
    end subroutine io_write1d


    !>------------------------------------------------------------
    !! Read a real type attribute from a named file from an optional variable
    !!
    !! If a variable name is given reads the named attribute of that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to read the attribute from
    !! @param   att_name    name of attribute to read
    !! @param   att_value   output value to be returned (real*4)
    !! @param   var_name    OPTIONAL name of variable to read attribute from
    !!
    !!------------------------------------------------------------
    module subroutine io_read_attribute_r(filename, att_name, att_value, var_name, error)
        implicit none
        character(len=*), intent(in) :: filename
        character(len=*), intent(in) :: att_name
        real*4, intent(out) :: att_value
        character(len=*), intent(in), optional :: var_name
        integer,          intent(out),optional :: error

        integer :: ncid, varid

        ! open the netcdf file
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)

        ! If a variable name was specified, get the varid of the variable
        ! else search for a global attribute
        if (present(var_name)) then
            call check(nf90_inq_varid(ncid, var_name, varid),var_name)
        else
            varid=NF90_GLOBAL
        endif

        ! Finally get the attribute data
        error = nf90_get_att(ncid, varid, att_name, att_value)

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine  io_read_attribute_r

    !>------------------------------------------------------------
    !! Read a integer type attribute from a named file from an optional variable
    !!
    !! If a variable name is given reads the named attribute of that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to read the attribute from
    !! @param   att_name    name of attribute to read
    !! @param   att_value   output value to be returned (integer)
    !! @param   var_name    OPTIONAL name of variable to read attribute from
    !!
    !!------------------------------------------------------------
    module subroutine io_read_attribute_i(filename, att_name, att_value, var_name, error)
        implicit none
        character(len=*), intent(in) :: filename
        character(len=*), intent(in) :: att_name
        integer, intent(out) :: att_value
        character(len=*), intent(in), optional :: var_name
        integer,          intent(out),optional :: error

        integer :: ncid, varid

        ! open the netcdf file
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)

        ! If a variable name was specified, get the varid of the variable
        ! else search for a global attribute
        if (present(var_name)) then
            call check(nf90_inq_varid(ncid, var_name, varid),var_name)
        else
            varid=NF90_GLOBAL
        endif

        ! Finally get the attribute data
        error = nf90_get_att(ncid, varid, att_name, att_value)

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine  io_read_attribute_i

    !>------------------------------------------------------------
    !! Read a character type attribute from a named file from an optional variable
    !!
    !! If a variable name is given reads the named attribute of that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to read the attribute from
    !! @param   att_name    name of attribute to read
    !! @param   att_value   output value to be returned (character)
    !! @param   var_name    OPTIONAL name of variable to read attribute from
    !!
    !!------------------------------------------------------------
    module subroutine io_read_attribute_c(filename, att_name, att_value, var_name, error)
        implicit none
        character(len=*), intent(in) :: filename
        character(len=*), intent(in) :: att_name
        character(len=*), intent(out) :: att_value
        character(len=*), intent(in), optional :: var_name
        integer,          intent(out),optional :: error

        integer :: ncid, varid

        ! open the netcdf file
        call check(nf90_open(filename, NF90_NOWRITE, ncid),filename)

        ! If a variable name was specified, get the varid of the variable
        ! else search for a global attribute
        if (present(var_name)) then
            call check(nf90_inq_varid(ncid, var_name, varid),var_name)
        else
            varid=NF90_GLOBAL
        endif

        ! Finally get the attribute data
        error = nf90_get_att(ncid, varid, att_name, att_value)

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine  io_read_attribute_c


    !>------------------------------------------------------------
    !! Write a real type attribute to a named file for an optional variable
    !!
    !! If a variable name is given writes the named attribute to that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to write the attribute to
    !! @param   att_name    name of attribute to write
    !! @param   att_value   output value to be written (real*4)
    !! @param   var_name    OPTIONAL name of variable to write attribute to
    !!
    !!------------------------------------------------------------
    module subroutine io_add_attribute_r(filename, att_name, att_value, varname)
        implicit none
        character(len=*), intent(in)           :: filename
        character(len=*), intent(in)           :: att_name
        real*4,           intent(in)           :: att_value
        character(len=*), intent(in), optional :: varname

        integer :: ncid
        integer :: varid

        ! open the netcdf file to add the attribute to
        call check (nf90_open(filename, NF90_WRITE, ncid), "opening:"//trim(filename))
        call check( nf90_redef(ncid) )

        ! if given a variable name find that variable ID to write the attribute to
        ! else the attribute will be global
        if (present(varname)) then
            call check( nf90_inq_varid(ncid, varname, varid))
        else
            varid = NF90_GLOBAL
        endif

        ! write the attribute to the file
        call check( nf90_put_att(ncid, varid, att_name, att_value), "writing attribute:"//trim(att_name)//" to:"//trim(filename))

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine io_add_attribute_r


    !>------------------------------------------------------------
    !! Write an integer type attribute to a named file for an optional variable
    !!
    !! If a variable name is given writes the named attribute to that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to write the attribute to
    !! @param   att_name    name of attribute to write
    !! @param   att_value   output value to be written (integer)
    !! @param   var_name    OPTIONAL name of variable to write attribute to
    !!
    !!------------------------------------------------------------
    module subroutine io_add_attribute_i(filename, att_name, att_value, varname)
        implicit none
        character(len=*), intent(in)           :: filename
        character(len=*), intent(in)           :: att_name
        integer,          intent(in)           :: att_value
        character(len=*), intent(in), optional :: varname

        integer :: ncid
        integer :: varid

        ! open the netcdf file to add the attribute to
        call check (nf90_open(filename, NF90_WRITE, ncid), "opening:"//trim(filename))
        call check( nf90_redef(ncid) )

        ! if given a variable name find that variable ID to write the attribute to
        ! else the attribute will be global
        if (present(varname)) then
            call check( nf90_inq_varid(ncid, varname, varid))
        else
            varid = NF90_GLOBAL
        endif

        ! write the attribute to the file
        call check( nf90_put_att(ncid, varid, att_name, att_value), "writing attribute:"//trim(att_name)//" to:"//trim(filename))

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine io_add_attribute_i


    !>------------------------------------------------------------
    !! Write an character type attribute to a named file for an optional variable
    !!
    !! If a variable name is given writes the named attribute to that variable
    !! otherwise the named attribute is assumed to be a global attribute
    !!
    !! @param   filename    netcdf file to write the attribute to
    !! @param   att_name    name of attribute to write
    !! @param   att_value   output value to be written (character)
    !! @param   var_name    OPTIONAL name of variable to write attribute to
    !!
    !!------------------------------------------------------------
    module subroutine io_add_attribute_c(filename, att_name, att_value, varname)
        implicit none
        character(len=*), intent(in)           :: filename
        character(len=*), intent(in)           :: att_name
        character(len=*), intent(in)           :: att_value
        character(len=*), intent(in), optional :: varname

        integer :: ncid
        integer :: varid

        ! open the netcdf file to add the attribute to
        call check (nf90_open(filename, NF90_WRITE, ncid), "opening:"//trim(filename))
        call check( nf90_redef(ncid) )

        ! if given a variable name find that variable ID to write the attribute to
        ! else the attribute will be global
        if (present(varname)) then
            call check( nf90_inq_varid(ncid, varname, varid))
        else
            varid = NF90_GLOBAL
        endif

        ! write the attribute to the file
        call check( nf90_put_att(ncid, varid, att_name, att_value), "writing attribute:"//trim(att_name)//" to:"//trim(filename))

        call check( nf90_close(ncid), "closing:"//trim(filename))
    end subroutine io_add_attribute_c


    !>------------------------------------------------------------
    !! Simple error handling for common netcdf file errors
    !!
    !! If status does not equal nf90_noerr, then print an error message and STOP
    !! the entire program.
    !!
    !! @param   status  integer return code from nc_* routines
    !! @param   extra   OPTIONAL string with extra context to print in case of an error
    !!
    !!------------------------------------------------------------
    subroutine check(status,extra)
        implicit none
        integer, intent ( in) :: status
        character(len=*), optional, intent(in) :: extra

        ! check for errors
        if(status /= nf90_noerr) then
            ! print a useful message
            print *, trim(nf90_strerror(status))
            if(present(extra)) then
                ! print any optionally provided context
                write(*,*) trim(extra)
            endif
            ! STOP the program execute
            stop "Stopped"
        end if
    end subroutine check

    !>------------------------------------------------------------
    !! Find an available file unit number.
    !!
    !! LUN_MIN and LUN_MAX define the range of possible LUNs to check.
    !! The UNIT value is returned by the function, and also by the optional
    !! argument. This allows the function to be used directly in an OPEN
    !! statement, and optionally save the result in a local variable.
    !! If no units are available, -1 is returned.
    !! Newer versions of fortran can do this automatically, but this keeps one thing
    !! a little more backwards compatible
    !!
    !! @param[out]  unit    OPTIONAL integer to store the file logical unit number
    !! @retval      integer a file logical unit number
    !!
    !!------------------------------------------------------------
    module integer function io_newunit(unit)
        implicit none
        integer, intent(out), optional :: unit
        ! local
        integer, parameter :: LUN_MIN=10, LUN_MAX=1000
        logical :: opened
        integer :: lun

        io_newunit=-1
        ! loop over all possible units until a non-open unit is found, then exit
        ! this should be re-written as a while loop instead of a do loop with an exit
        ! but it ain't broke so...
        do lun=LUN_MIN,LUN_MAX
            inquire(unit=lun,opened=opened)
            if (.not. opened) then
                io_newunit=lun
                exit
            end if
        end do
        if (present(unit)) unit=io_newunit
    end function io_newunit

end submodule io_routines_implementation
