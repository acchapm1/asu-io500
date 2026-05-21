-------------------------------------------------------------------------------
-- BLAME: Alan <acchapm1@asu.edu>
-- BUILD_DATE: 2025-06-19
-- PATCH_DATE: 2026-05-20
-- BUILD_PATH: /packages/apps/build/openmpi/5.0.8
-------------------------------------------------------------------------------
--
-- Drop-in replacement for /packages/modulefiles/apps/openmpi/5.0.8.lua.
--
-- Changes vs. the deployed module (2026-05-20):
--   1. Prepend the HPC-X hcoll directory to LD_LIBRARY_PATH so that
--      libhcoll.so.1 and libocoms.so.0 (both DT_NEEDED of this module's
--      own libmpi.so.40) resolve without the user having to set
--      LD_LIBRARY_PATH manually. Without this fix, ANY program linked
--      against /packages/apps/openmpi/5.0.8/lib/libmpi.so.40 fails at
--      startup with:
--        error while loading shared libraries: libhcoll.so.1: cannot
--        open shared object file: No such file or directory
--      (or the same error for libocoms.so.0).
--   2. Also prepend the hcoll dir to LIBRARY_PATH so link-time symbol
--      resolution of transitive DT_NEEDED entries from libmpi succeeds
--      under ld's default --no-allow-shlib-undefined.
--   3. Add family("mpi") to mirror openmpi/5.0.8-gcc-15.2.0.lua, so
--      Lmod refuses to load two MPI modules simultaneously.
--   4. Set HPCX_HCOLL_DIR to mirror openmpi/4.1.5.lua's convention.
--
-- Background and the underlying RUNPATH-inheritance issue are documented
-- in:  asu-io500/docs/mpi-hcoll-findings.md
--
-- If RC moves HPC-X 2.25.1 (or rebuilds libmpi against a different HPC-X
-- version), update HPCX_HCOLL_LIB below. 2.13.1, 2.21.3-lts, 2.23, 2.25.1,
-- and 2.26 are all symbol-compatible with the libmpi.so.40 in this build
-- (verified by linking `mpicc /tmp/t.c` against each — see
-- mpi-hcoll-findings.md for the test method).

-- Define module metadata
local app_path     = "/packages/apps/openmpi/5.0.8"
local _name        = "openmpi"
local _version     = "5.0.8"

-- HPC-X hcoll path expected by this build's libmpi.so.40
-- (DT_NEEDED libhcoll.so.1, libocoms.so.0).
local HPCX_HCOLL_DIR = "/packages/apps/hpcx/2.25.1/doca/hcoll"
local HPCX_HCOLL_LIB = pathJoin(HPCX_HCOLL_DIR, "lib")

local _description = [===[

  The Open MPI Project is an open source Message Passing Interface
  implementation that is developed and maintained by a consortium of academic,
  research, and industry partners. Open MPI is therefore able to combine the
  expertise, technologies, and resources from all across the High Performance
  Computing community in order to build the best MPI library available. Open MPI
  offers advantages for system and software vendors, application developers and
  computer science researchers.

  For more information, visit:
  https://www.open-mpi.org/

  HPC-X note: this build's libmpi has hard DT_NEEDED entries on libhcoll.so.1
  and libocoms.so.0, which live under HPC-X 2.25.1 (doca/hcoll/lib). This
  module prepends that directory to LD_LIBRARY_PATH so the deps resolve.
]===]

local _help  = string.format([===[

  Name: %s
  Version:  %s
  ## Description ##
  %s
]===],
  _name,
  _version,
  _description
)

whatis(_help)
help(_help)

-- Prevent loading multiple MPIs simultaneously.
family("mpi")

-- Generic path, library, and include environment variables.
prepend_path("PATH",            pathJoin(app_path, "bin"))
prepend_path("LD_LIBRARY_PATH", pathJoin(app_path, "lib"))
prepend_path("CPATH",           pathJoin(app_path, "include"))
prepend_path("MANPATH",         pathJoin(app_path, "share/man"))

-- HPC-X hcoll / ocoms resolution (the fix).
-- LD_LIBRARY_PATH covers runtime; LIBRARY_PATH covers link time so that
-- consumers like io500's IOR/mdtest configure can pass their conftests.
prepend_path("LD_LIBRARY_PATH", HPCX_HCOLL_LIB)
prepend_path("LIBRARY_PATH",    HPCX_HCOLL_LIB)
setenv("HPCX_HCOLL_DIR", HPCX_HCOLL_DIR)

-- User message to stderr upon module load
if (mode() == "load") then

  local _loaded  = string.format([===[
===============================================================================
Loaded: %s %s
%s
===============================================================================
    ]===],
    _name,
    _version,
    _description
    )
  LmodMessage(_loaded)

  -- Best-effort sanity check: warn the user if HPC-X 2.25.1 has been
  -- moved or removed since this module was patched, since the binary
  -- will then fail at startup with a libhcoll/libocoms not-found error.
  if not isDir(HPCX_HCOLL_LIB) then
    LmodWarning(string.format(
      "openmpi/5.0.8: HPC-X hcoll dir not found at %s. " ..
      "libmpi.so.40 will fail to load libhcoll.so.1/libocoms.so.0. " ..
      "Contact RC, or override LD_LIBRARY_PATH to a working HPC-X hcoll dir.",
      HPCX_HCOLL_LIB))
  end

end
