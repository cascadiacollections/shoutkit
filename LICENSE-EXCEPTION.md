# Additional permission under GNU GPL version 3, section 7

This file applies to the parts of this repository licensed under the GNU General Public License,
version 3 (the root [`LICENSE`](LICENSE)): the Holmdel app target, the feature packages, and
`Packages/LiveActivity`. It does not apply to the MIT-licensed ShoutKit packages, which need no
exception.

> As an additional permission under section 7 of the GNU General Public License, version 3, you
> may convey this Program, or any covered work based on it, through an app distribution service
> (including the Apple App Store, TestFlight, and Google Play) whose terms of service, technical
> measures, or usage rules restrict recipients — for example by digital rights management, by
> limiting the number of devices, or by forbidding further redistribution — provided that you
> also make the Corresponding Source of the work available to those recipients under the terms
> of this License, without such restrictions.
>
> If you modify this Program, you may extend this additional permission to your version, but you
> are not obligated to do so. If you do not wish to do so, delete this additional permission from
> your version.

## Why

GPL-3.0 section 10 forbids imposing "further restrictions" on recipients. The App Store's usage
rules (FairPlay DRM, device limits, the standard EULA) arguably do that, which is why GPL apps
have been pulled from it before. Kevin T. Coughlin holds the copyright in most of this code and
can publish it on the App Store regardless. Contributions signed off under the DCO, though, are
licensed to the project under GPL-3.0 like anyone else's. This permission makes sure the App
Store build can include them, and lets forks publish on stores too, as long as the source stays
free.
