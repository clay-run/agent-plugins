# Company vertical → industry mapping

Use these `industry` values when a workflow step decides a company's vertical (for example "is this a software company?"). A company counts as the vertical when its `industry` is one of the listed values. These are the same defaults Clay Search uses.

| Vertical                             | Counts as                                                                                                                    | Does not count                |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| SaaS, software                       | Software Development; Technology, Information and Internet                                                                   | IT Services and IT Consulting |
| tech companies, technology companies | Software Development; Technology, Information and Internet; IT Services and IT Consulting; Technology, Information and Media |                               |
| fintech                              | Financial Services; Banking                                                                                                  |                               |
| healthcare companies                 | Hospitals and Health Care; Medical Practices; Medical Devices; Pharmaceutical Manufacturing                                  |                               |
| banks                                | Banking; Investment Banking                                                                                                  |                               |
