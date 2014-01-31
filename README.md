GrokinNotes
===========
A simple note taking app experiment which uses Google Drive as the cloud based data
storage and synchronization mechanism.

### Requirements

* The app's deployment target is for iOS 7.0
* A Google Drive account is needed for note synchronization.

### Notes

Configuration for Google Drive is stored in a plist which is not included in this
repository:

	GrokinNotes/GrokinNotes/Resources/GoogleConfiguration.plist
	
The plist should have two keys: `client_id` and `client_secret` which should have the
appropriate Google credentials as `String` values. If this file is not present or does not
contain the needed credentials the app will present an unrecoverable error.

A sample `GoogleConfiguration.plist` is provided (with fake values):

	GrokinNotes/GrokinNotes/GoogleConfiguration.plist

Steps to create the needed Google credentials are [available](SampleConfigs/GoogleREADME.md).
	
Similarly, configuration for TestFlight is stored in a plist which is also not included in
this repository (but is optional):

	GrokinNotes/GrokinNotes/Resources/TestFlightConfiguration.plist

The plist should have an `enabled` key of type `BOOL` which dictates if TestFlight will be
used.
Also it should have an `app_token` key representing the `String` value of the TestFlight
application token.

A sample `TestFlightConfiguration.plist` is provided (with fake values):

	GrokinNotes/GrokinNotes/TestFlightConfiguration.plist

#### Future Direction

There's plenty of additional features and user interface aspects to be developed. A few
ideas present themselves:

* Handle more than plain text files.
* Allow folder hierarchies.
* Show login status on main interface.
* Allow switching between multiple accounts.
* Export of notes (email, social, etc.).
* Google Drive specific features (comments, sharing, etc.).
* Optimize the metadata returned from GoogleDrive (remove unneeded metadata from being
returned by the request).
* Prevent synchronization attempts if we are not authenticated or do not have network
connectivity.
* Handle duplicate note titles. This is potentially tricky, if we will continue to try to
keep note titles tied to the note filename on iOS since the filesystem will prevent files
with the same name, while Google Drive has no such limitation. Perhaps the files can be
stored in a non-user visible location (not in "Documents") with unique filenames and
sym-linked to Documents with title names. This might work, but we still have to adjust the
duplicated filenames somehow.

#### Known Issues

* A drop shadow should be present on the main view once the menu view is displayed (but
does not appear).
* Duplicate note titles cause name space collisions on the iOS filesystem and will have to
be cleared by renaming similarly named notes using the Google Drive interface directly.
* The main table view is refreshed by brute force. It will need to be made smarter by
performing animated inserts/deletes/updates.

### Disclaimer and Licence

* This work is licensed under the [Creative Commons Attribution 3.0 Unported License](http://creativecommons.org/licenses/by/3.0/).
  Please see the included LICENSE.txt for complete details.

### About
A professional iOS engineer by day, my name is Levi Brown. Authoring a technical blog
[grokin.gs](http://grokin.gs), I am reachable via:

Twitter [@levigroker](https://twitter.com/levigroker)  
App.net [@levigroker](https://alpha.app.net/levigroker)  
Email [levigroker@gmail.com](mailto:levigroker@gmail.com)  

Your constructive comments and feedback are always welcome.
