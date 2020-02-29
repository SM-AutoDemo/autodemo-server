#if defined _autodemo_included
 #endinput
#endif
#define _autodemo_included

/**
 * Sends a HTTP(S) request with an event.
 *
 * @param sEvent        Event name.
 * @param iParamsLenght Params lenght.
 * @param sParams       Event parameters. Must be in the JSON structure.
 */
native void AutoDemo_SendHTTPQuery(const char[] sEvent, int iParamsLenght, char[] sParams, any ...);



public SharedPlugin __pl_autodemo = 
{
	name = "autodemo",
	file = "autodemo.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_autodemo_SetNTVOptional()
{
	MarkNativeAsOptional("AutoDemo_SendHTTPQuery");
}
#endif