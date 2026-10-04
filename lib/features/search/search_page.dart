import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../route/route_preview_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController =
      TextEditingController();

  final List<Destination> _destinations = [
    const Destination(
      name: 'Khoa Ngoại Thần Kinh',
      location: 'Tầng 4, Khu B',
      distance: '120m',
    ),
    const Destination(
      name: 'Nhà vệ sinh (Nam)',
      location: 'Tầng 1, Khu A',
      distance: '15m',
    ),
    const Destination(
      name: 'Quầy thuốc Số 3',
      location: 'Tầng 1, Sảnh chính',
      distance: '45m',
    ),
    const Destination(
      name: 'Phòng Cấp cứu',
      location: 'Tầng trệt, Khu C',
      distance: '85m',
    ),
  ];

  List<Destination> get _filteredDestinations {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _destinations;
    }

    return _destinations.where((destination) {
      return destination.name.toLowerCase().contains(query) ||
          destination.location.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _selectDestination(Destination destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePreviewPage(
          destination: destination.name,
          location: destination.location,
          distance: destination.distance,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _filteredDestinations;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // =========================
            // HEADER + SEARCH
            // =========================
            Container(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16,
              ),
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border,
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText:
                              'Tìm địa điểm, phòng...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // =========================
            // RESULTS
            // =========================
            Expanded(
              child: results.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        20,
                        16,
                        32,
                      ),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(
                            left: 8,
                            bottom: 14,
                          ),
                          child: Text(
                            'GỢI Ý',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),

                        ...results.map(
                          (destination) =>
                              Padding(
                            padding:
                                const EdgeInsets.only(
                              bottom: 10,
                            ),
                            child: _destinationCard(
                              destination,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destinationCard(
    Destination destination,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        _selectDestination(destination);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
                size: 21,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    destination.location,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color:
                    AppColors.accent.withValues(
                  alpha: 0.10,
                ),
                borderRadius:
                    BorderRadius.circular(8),
              ),
              child: Text(
                destination.distance,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 52,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 14),
            Text(
              'Không tìm thấy địa điểm',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Hãy thử tìm với tên địa điểm hoặc phòng khác.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Destination {
  final String name;
  final String location;
  final String distance;

  const Destination({
    required this.name,
    required this.location,
    required this.distance,
  });
}