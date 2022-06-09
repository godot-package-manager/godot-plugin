#! /bin/bash

dirname="addons"
gpm_dir=$dirname"/godot-package-manager"

#TODO: Change to this repo once accepted
#gpm_url="https://github.com/you-win/godot-package-manager"
gpm_url="https://raw.githubusercontent.com/LunCoSim/godot-package-manager"
package_file_url="https://raw.githubusercontent.com/LunCoSim/godot-package-manager/master/godot.package"
exec_file_url="https://raw.githubusercontent.com/LunCoSim/godot-package-manager/master/gpm"

PACKAGE_FILE="godot.package"
GPM_FILE="gpm"

branch="master"

gpm_files=( "godot_package_manager.gd" "main.gd" "main.tscn" "plugin.cfg" "plugin.gd" "adaptors/npmjs.gd" "utils/utils.gd" "utils/utils.gd" "utils/fs.gd" "utils/http.gd" "gpm.gd" "classes/advanced-expression.gd" "classes/error.gd" "classes/failed-packages.gd" "classes/hooks.gd" "classes/result.gd" )

create_folder() {
    folder = $1
    echo "Initializing Godot Packpage Manager"
    echo "Using /"$folder" directory for GPM"

    if [ ! -d "$folder" ]
    then
        echo $folder" doesn't exist. Creating now"
        mkdir ./$folder
        echo $folder" created"
    else
        echo $folder" exists"
    fi

}

#TBD: Check that file "project.godot" existis in this folder

#Creating directiries for the gpm
create_folder $dirname
create_folder $gpm_dir

#Downloading files
for i in "${gpm_files[@]}"
do
	file=$gpm_url"/"$branch"/"$gpm_dir"/"$i
    echo "Starting to download: "$file
    dir_to_save=./$gpm_dir

    #splitting file to get folders
    IFS='/' read -ra folders <<< "$i"
    
    for folder in "${folders[@]::${#folders[@]}-1}"
    do
        dir_to_save=$dir_to_save/$folder
    done

    echo "Folders: "${#folders[@]}
    echo $dir_to_save

    wget $file -P $dir_to_save
done

#Downloading godot.package
if ! test -f "$PACKAGE_FILE"; then
    wget $package_file_url
fi

if ! test -f "$GPM_FILE"; then
    wget $exec_file_url
fi

chmod +x ./$GPM_FILE

# #TBD autoactivate plagin in godot.project
#TBD add to .gitignore
echo "Do not forget to add addons/ to .gitignore"