#! /bin/bash

dirname="addons"
gpm_dir=$dirname"/godot-package-manager"

#TODO: Change to this repo once accepted
#gpm_url="https://github.com/you-win/godot-package-manager"
gpm_url="https://raw.githubusercontent.com/LunCoSim/godot-package-manager"
package_file_url="https://raw.githubusercontent.com/you-win/godot-package-manager/master/godot.package"
branch="master"

gpm_files=( "godot_package_manager.gd" "main.gd" "main.tscn" "plugin.cfg" "plugin.gd" )

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

#Creating directiries for the gpm
create_folder $dirname
create_folder $gpm_dir

#Downloading files
for i in "${gpm_files[@]}"
do
	file=$gpm_url"/"$branch"/"$gpm_dir"/"$i
    echo "Starting to download: "$file
    wget $file -P ./$gpm_dir
done

#Downloading godot.package
wget $package_file_url

#TBD autoactivate plagin in godot.project
#TBD add to .gitignore
echo "Do not forget to add addons/ to .gitignore"