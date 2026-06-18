Set-Abbr g git
Set-Abbr ga "git add"
Set-Abbr gaa "git add --all"
Set-Abbr gau "git add --update"

Set-Abbr gb "git branch"
Set-Abbr gbv "git branch -vv"
Set-Abbr gbr "git branch -r"
Set-Abbr gba "git branch -a"
Set-Abbr gbd "git branch -d"
Set-Abbr gbD "git branch -d -f"

Set-Abbr gc "git commit"
Set-Abbr gcm "git commit -m"
Set-Abbr gacm "git commit -am"
Set-Abbr gca "git commit --amend"
Set-Abbr gcaa "git commit --amend -a"

Set-Abbr gco "git checkout"
Set-Abbr gcb "git checkout -b"
Set-Abbr gcor "git checkout --recurse-submodules"

Set-Abbr gs "git status"
Set-Abbr gss "git status -s"
Set-Abbr gsb "git status -sb"

Set-Abbr gd "git diff"
Set-Abbr gdca "git diff --cached"
Set-Abbr gdcw "git diff --cached --word-diff"
Set-Abbr gds "git diff --staged"

Set-Abbr glg "git lg"

Set-Abbr gl "git pull"
Set-Abbr gpr "git pull -r"
Set-Abbr gpra "git pull -r --autostash"
Set-Abbr gprav "git pull -r --autostash -v"

Set-Abbr gp "git push"
Set-Abbr gpd "git push --dry-run"

Set-Abbr gm "git merge"
Set-Abbr gma "git merge --abort"
Set-Abbr gmc "git merge --continue"

Set-Abbr grb "git rebase"
Set-Abbr grba "git rebase --abort"
Set-Abbr grbc "git rebase --continue"

Set-Abbr gcp "git cherry-pick"
Set-Abbr gcpa "git cherry-pick --abort"
Set-Abbr gcpc "git cherry-pick --continue"

Set-Abbr grh "git reset"
Set-Abbr grhh "git reset --hard"
Set-Abbr gru "git reset --"
Set-Abbr gclean! "git reset --hard; and git clean -df"

Set-Abbr gsu "git submodule update"
Set-Abbr gsur "git submodule update --recursive"
Set-Abbr gsuri "git submodule update --recursive --init"

Set-Abbr glf "git lfs"
Set-Abbr glfi "git lfs install"
Set-Abbr glfls "git lfs ls-files"
Set-Abbr glfs "git lfs status"
Set-Abbr glfup "git lfs pull; git lfs checkout"
Set-Abbr glfpr "git lfs prune"