GrokinNotes
===========
A simple note taking app experiment which uses Google Drive as the cloud based data
storage and synchronization mechanism.

### Notes

Configuration for Google Drive is stored in a plist which is not included in this
repository:

	GrokinNotes/GrokinNotes/Resources/GoogleConfiguration.plist
	
The plist should have two keys: `client_id` and `client_secret` which should have the
appropriate Google credentials as `String` values. If this file is not present or does not
contain the needed credentials the app will present an unrecoverable error.

A sample `GoogleConfiguration.plist` is provided (with fake values):

	GrokinNotes/GrokinNotes/GoogleConfiguration.plist
	
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

#### Known Issues

* The synchronization code is a work in progress and is by no means working fully as
intended.
* A race condition exists such that when a new note is created and it's title changed
locally the title may revert to "Untitled" as a server update occurs.
* A crashing issue exists when updating the table view as a server update is in progress.
This is likely due to a race condition caused by concurrent execution of note updates from
the remote. A possible solution is to group the changes into a batch and send the batch
along in the notification rather than sending individual notifications. This is most
likely desired anyway since it will cause less visual "thrash" to the user as updates
occur.
* Currently, attempting to delete a note will block the refresh indefinitely, and will
persist since the file is marked as deleted locally.
* A drop shadow should be present on the main view once the menu view is displayed (but
does not appear).

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
