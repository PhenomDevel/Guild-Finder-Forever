local _, ns = ...

-- Development checkout: this folder is not packaged (see .pkgmeta and the
-- #@do-not-package@ block in the toc), so release builds never set this.
ns.DEV = true
