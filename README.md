# Pumice Ubuntu 26.04
This repo has a kiwi description to produce an offline installable desktop with a small selection of software running Gnome with a few extensions. It is easy to modify and expand upon. I have tested this on Ubuntu 26.04 only, due to `snapd` usage it can not be build in a docker or podman container.

## Prepare to build
Since ```kiwi``` in the stock repo is likely too old we install ```kiwi``` from ```git``` instead:
```
sudo apt install git mtools python3-poetry xorriso
git clone https://github.com/OSInside/kiwi
cd kiwi && PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring poetry install && cd ..
sudo ln -sf "$(poetry env info --path)/bin/kiwi-ng" /usr/local/bin/kiwi-ng
```

## Building the iso
Clone the repo and edit the packages (config.xml), build script (config.sh) and check out the root folder and make adjustments where needed.
```
git clone https://github.com/zearp/pumice-ubuntu && cd pumice-ubuntu
nano config.sh && nano config.xml && nano images.sh && ls -lha root
```
To build the ```iso``` simply run ```make``` and wait for the process to finish. This will take a while, you can track progress in more detail by tailing the log file in a new session or terminal running the ```tail -f ~/pumice-ubuntu/build-tmp/image-root.log``` command.

## Finishing up:
Copy the generated image from ```outdir``` and if wanted run ```make clean``` to clean up the ```build-tmp``` and ```outdir``` directories.

Remove kiwi, assuming it was installed from ```~/kiwi```:
```
sudo rm -f /usr/local/bin/kiwi-ng
cd ~/kiwi && poetry env remove --all && cd .. && rm -rf ~/kiwi
```
There is also an apt-cache created by ```kiwi-ng``` in ```/var/cache/kiwi``` which can be deleted though leaving it in place will speed up rebuilds.

## Misc
A collection of different things.
### Check for updates and install them or upgrade to a newer version:
```
sudo apt update && sudo apt upgrade
```
Remove unused dependencies/orphans:
```
sudo apt --purge autoremove
```
To update to a new release, from say 26.04 to 28.04 do the following:
```
sudo do-release-upgrade
```
### Check for firmware updates for supported hardware:
```
sudo fwupdmgr refresh
sudo fwupdmgr get-updates
# make sure you need/want these updates!
sudo fwupdmgr update
```
### Sync screen setting with login screen (gdm):
```
sudo mkdir /var/lib/gdm3/.config && sudo cp ~/.config/monitors.xml /var/lib/gdm3/.config/
```
### Check sleep mode
This step is optional but I never skip it. There are differnet sleep modes and the available modes depend on your machine and BIOS settings. For desktops I try to use ```S0``` (s2idle) sleep if possible and for laptops ```S3``` (deep). Some sleep modes use more energy than others, set sleep to ```S3``` to suspend to RAM which is usally available on all systems. For maximum savings ```S4``` suspend to disk could be used but it may not work on all systems.

To check which sleep state is currently used run ```cat /sys/power/mem_sleep``` and check the active and available modes the active sleep mode is surrounded by ```[ ]``` brackets. 

If it is set to how you like it do a sleep cycle test by suspending the machine and make sure it actually enters sleep. Often indicated by the power led chaging state to slowly pulsing or it's colour chaging to amber. If your preffered sleep mode  works we're done.

If it doesn't boot into the BIOS and look for a ACPI options related to sleep. For example to enable ```S0``` a setting called "S0 idle capability" or something similar will be listed. On some systems the ```S0``` setting might be called "S0ix" or "modern standby" and these settings usally but not always found in ACPI and/or power related setting menu's. Enable the settings you wish to be available and reboot and run the command to see sleep states again. It might be needed to set a kernel flag to select the default you want if not done automatically.
```
sudo nano /etc/default/grub
```

Add ```mem_sleep_default=s2idle``` to the ```GRUB_CMDLINE_LINUX_DEFAULT=""``` list of parameters, run ```sudo update-grub``` and reboot to apply.

Replace ```s2idle``` with the sleep mode you want to use by default and reboot. It is possible sleep seems working but sleep will be "fake" in a sense that it doesn't go into any deep sleep mode. Often easy to spot by the power led not going into a fading or colour change state and fans not turning off. On some passivle cooled systems it may be difficult to test this without fans as not all systems change the power led on sleep. If it wakes near instantly it's most likely not working. To undo just replace ```--args``` with ```--remove-args``` and reboot.

For more information about these sleep states refer to [this](https://www.kernel.org/doc/Documentation/power/states.txt) document. If you want to maximise pwoer savings use either ```S3``` which suspends to RAM which is the default when bios does not enable/set ```S0``` sleep states or ```S4``` which suspends to disk instead. Use whatever sleep mode suits best. As shown above you can add a kernel parameter to declare your preference. Just replace ```s2idle``` with either ```deep``` or ```disk``` in the ```grubby``` command.

> Make sure to always test the sleep mode when chaging it.

### Fully disable sleep
Be sure to also disable it the settings app. These commands should not be needed but I've had machines acting as server go to sleep despite it being disabled in settings.
```
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

# Tip and tricks:
- Explore the ```root``` folder to get an idea of the possibilities, simply delete to use defaults if applicable
- You can customise the file system by adding, removing or editing files in the ```root``` folder
- Use the ```dconf dump / > gsettings.txt ``` command to export settings of compatible apps to use in ```98-pumice```
- Read the ```kiwi``` docs: https://osinside.github.io/kiwi/image_description/elements.html
- By changing the default boot target to text mode (```sudo systemctl set-default multi-user.target```) you can free up some resources for server usage.
