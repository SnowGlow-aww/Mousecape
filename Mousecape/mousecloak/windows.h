//
//  windows.h
//  Mousecape
//
//  Converts Windows cursor themes (.ani and .cur files) to capes.
//

#ifndef Mousecape_windows_h
#define Mousecape_windows_h

// A Windows cursor theme is a folder of .ani/.cur files, usually with an install.inf saying which file
// is which pointer. The folder, its .inf or the cursor files themselves can be given.
extern BOOL MCIsWindowsCursorPath(NSString *path);

// A cape made from the given paths, or nil with an error. metadata may set the name, author, identifier
// and version like it does for MightyMouse; the rest come from the theme.
extern NSDictionary *createCapeFromWindowsCursors(NSArray *paths, NSDictionary *metadata, NSError **error);

#endif
