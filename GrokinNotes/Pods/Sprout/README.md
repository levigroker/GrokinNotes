Sprout
===========
 Used to bootstrap the (excellent) [CocoaLumberjack](https://github.com/robbiehanson/CocoaLumberjack) logging framework.

### Installing

If you're using [CocoPods](http://cocopods.org) it's as simple as adding this to your `Podfile`:

	pod 'Sprout', '~> 1.0'

### Documentation

 In the simplest case, setup is just:

* Add `Sprout.h` to your precompiled header:


		#ifdef __OBJC__
		#import <Foundation/Foundation.h>
		//Third Party
		#import "Sprout.h"
		#endif

* Start Logging in your `application:didFinishLaunchingWithOptions:` UIApplicationDelegate

		- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
		{
			//Initialize logging
			[[Sprout sharedInstance] startLogging];
			...

* Define `DEBUG`
 In your Preprocessor Macros target build settings, define `DEBUG=1` (this may not be needed, as it is a default setting in later XCode project templates).

* _Run!_

After the above setup, you should be able to run and see:

		CocoaLumberjack loggers initialized!

appear in your console.

#### TestFlight Usage
[TestFlight](http://testflightapp.com) is a great tool, and Sprout has support for it.

If you `#define TESTFLIGHT` (or define `TESTFLIGHT` in your build settings), Sprout will add the `TestFlightLogger` to send log messages to the `TFLog` TestFlight SDK logger at your current log level.

__NOTE:__ If you define `TESTFLIGHT` you must have `libTestFlight.a` linked or you'll get a linker error (see https://testflightapp.com/sdk/doc/ for information on installing TestFlight)

__NOTE:__ If you're using TestFlight you should initialize Sprout before calling `TestFlight takeOff:`

### Version History

* 1.0 - March 1, 2013
 * Initial public release.
* 1.1 - September 20, 2013
  * Added dynamic log level support.
  * Added basic app, device, and OS logging functionality.

### Licence

This work is licensed under the [Creative Commons Attribution 3.0 Unported License](http://creativecommons.org/licenses/by/3.0/).
Please see the included LICENSE.txt for complete details.

### About
A professional iOS engineer by day, my name is Levi Brown. Authoring a technical
blog [grokin.gs](http://grokin.gs), I am reachable via:

Twitter [@levigroker](https://twitter.com/levigroker)  
App.net [@levigroker](https://alpha.app.net/levigroker)  
EMail [levigroker@gmail.com](mailto:levigroker@gmail.com)  

Your constructive comments and feedback are always welcome.
