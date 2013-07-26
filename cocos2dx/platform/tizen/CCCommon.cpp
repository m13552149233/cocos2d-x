/****************************************************************************
Copyright (c) 2013 cocos2d-x.org
Copyright (c) 2013 Lee, Jae-Hong

http://www.cocos2d-x.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
****************************************************************************/

#include "platform/CCCommon.h"
#include "CCStdC.h"
#include <FBaseLog.h>

NS_CC_BEGIN

#define MAX_LEN         (cocos2d::kMaxLogLen + 1)

// XXX deprecated
void CCLog(const char * pszFormat, ...)
{
    char szBuf[MAX_LEN];

    va_list ap;
    va_start(ap, pszFormat);
    vsnprintf(szBuf, MAX_LEN, pszFormat, ap);
    va_end(ap);

    // Strip any trailing newlines from log message.
    size_t len = strlen(szBuf);
    while (len && szBuf[len-1] == '\n')
    {
      szBuf[len-1] = '\0';
      len--;
    }

    AppLog("cocos2d-x debug info [%s]\n",  szBuf);
}

void log(const char * pszFormat, ...)
{
    char szBuf[MAX_LEN];

    va_list ap;
    va_start(ap, pszFormat);
    vsnprintf(szBuf, MAX_LEN, pszFormat, ap);
    va_end(ap);

    // Strip any trailing newlines from log message.
    size_t len = strlen(szBuf);
    while (len && szBuf[len-1] == '\n')
    {
      szBuf[len-1] = '\0';
      len--;
    }

    AppLog("cocos2d-x debug info [%s]\n",  szBuf);
}

void MessageBox(const char * pszMsg, const char * pszTitle)
{
    log("%s: %s", pszTitle, pszMsg);
}

void LuaLog(const char * pszFormat)
{
    puts(pszFormat);
}

NS_CC_END
